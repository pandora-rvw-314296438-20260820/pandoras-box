import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "wait_for_plp_android_ready", Path(__file__).with_name("wait_for_plp_android_ready.py"))
ready = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ready)

# Relevant lines from the failed fb6 installed-run dump; ephemeral record/window
# tokens are replaced with fixture identifiers. The readiness values are actual.
FAILED_LAUNCH = """ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)
  * Task{fixture-target}
    topResumedActivity=ActivityRecord{fixture-target u0 com.banataosystems.pandora.plp/.MainActivity t8}
    * Hist  #0: ActivityRecord{fixture-target u0 com.banataosystems.pandora.plp/.MainActivity t8}
      packageName=com.banataosystems.pandora.plp processName=com.banataosystems.pandora.plp
      mActivityComponent=com.banataosystems.pandora.plp/.MainActivity
      state=RESUMED delayedResume=false finishing=false
      windows=[Window{fixture-main u0 com.banataosystems.pandora.plp/com.banataosystems.pandora.plp.MainActivity}, Window{fixture-splash u0 Splash Screen com.banataosystems.pandora.plp}]
      mVisibleRequested=true mVisible=true mClientVisible=true reportedDrawn=false reportedVisible=false
      mNumInterestingWindows=1 mNumDrawnWindows=0 allDrawn=false lastAllDrawn=false)
      startingData=SplashScreenStartingData{fixture-start waitForSyncTransactionCommit=false removeAfterTransaction= 0} firstWindowDrawn=false mIsExiting=false
      startingWindow=Window{fixture-splash u0 Splash Screen com.banataosystems.pandora.plp} startingSurface=com.android.server.wm.StartingSurfaceController$StartingSurface@fixture startingDisplayed=true startingMoved=false
  * Task{fixture-launcher}
    * Hist  #1: ActivityRecord{fixture-other u0 com.google.android.apps.nexuslauncher/.NexusLauncherActivity t7}
      packageName=com.google.android.apps.nexuslauncher
      state=PAUSED delayedResume=false finishing=false
      mVisibleRequested=false mVisible=false mClientVisible=false reportedDrawn=false reportedVisible=false
      mNumInterestingWindows=1 mNumDrawnWindows=1 allDrawn=true lastAllDrawn=false)
      startingData=null firstWindowDrawn=true mIsExiting=false
ActivityTaskSupervisor state:
  mCurrentFocus=Window{fixture-main u0 com.banataosystems.pandora.plp/com.banataosystems.pandora.plp.MainActivity}
  mFocusedApp=ActivityRecord{fixture-target u0 com.banataosystems.pandora.plp/.MainActivity t8}
"""


def drawn_fixture():
    """Synthetic positive fixture, not a claimed installed-device readback."""
    return FAILED_LAUNCH.replace(
        ', Window{fixture-splash u0 Splash Screen com.banataosystems.pandora.plp}', '').replace(
        'reportedDrawn=false reportedVisible=false', 'reportedDrawn=true reportedVisible=true', 1).replace(
        'mNumDrawnWindows=0 allDrawn=false', 'mNumDrawnWindows=1 allDrawn=true').replace(
        'startingData=SplashScreenStartingData{fixture-start waitForSyncTransactionCommit=false removeAfterTransaction= 0} firstWindowDrawn=false',
        'startingData=null firstWindowDrawn=true').replace(
        '      startingWindow=Window{fixture-splash u0 Splash Screen com.banataosystems.pandora.plp} startingSurface=com.android.server.wm.StartingSurfaceController$StartingSurface@fixture startingDisplayed=true startingMoved=false\n', '')


class FakeClock:
    def __init__(self):
        self.now = 0

    def clock(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class DrawnReadinessTests(unittest.TestCase):
    def test_actual_failure_resumed_and_focused_is_not_drawn(self):
        result = ready.observe_dump(FAILED_LAUNCH)
        self.assertFalse(result['ready'])
        self.assertTrue(result['flags']['resumed'])
        self.assertTrue(result['flags']['focused'])
        for flag in ('reportedVisible', 'reportedDrawn', 'allDrawn', 'firstWindowDrawn', 'no_starting_surface'):
            self.assertFalse(result['flags'][flag], flag)
        self.assertEqual(result['target_activity_count'], 1)

    def test_positive_fixture_requires_all_exact_target_properties(self):
        self.assertTrue(ready.observe_dump(drawn_fixture())['ready'])
        for flag in ready.REQUIRED_TRUE:
            with self.subTest(flag=flag):
                self.assertFalse(ready.observe_dump(drawn_fixture().replace(flag + '=true', flag + '=false', 1))['ready'])
                self.assertFalse(ready.observe_dump(drawn_fixture().replace(flag + '=true', '', 1))['ready'])
        for old, new in (('state=RESUMED', 'state=PAUSED'), ('finishing=false', 'finishing=true'),
                         ('startingData=null', 'startingData=StartingData{fixture}')):
            self.assertFalse(ready.observe_dump(drawn_fixture().replace(old, new, 1))['ready'])

    def test_drawn_launcher_cannot_fill_missing_target_flags(self):
        candidate = drawn_fixture().replace('reportedDrawn=true reportedVisible=true', '', 1).replace(
            'mNumDrawnWindows=1 allDrawn=true lastAllDrawn=false)', '', 1).replace(
            'startingData=null firstWindowDrawn=true mIsExiting=false', '', 1)
        candidate = candidate.replace('state=PAUSED', 'state=RESUMED').replace('reportedDrawn=false reportedVisible=false', 'reportedDrawn=true reportedVisible=true')
        self.assertFalse(ready.observe_dump(candidate)['ready'])
        self.assertIsNone(ready.observe_dump(candidate)['flags']['allDrawn'])

    def test_wrong_target_wrong_focus_and_duplicate_target_fail_closed(self):
        good = drawn_fixture()
        for text in (good.replace(ready.PACKAGE, ready.PACKAGE + '.lookalike'),
                     good.replace('/.MainActivity', '/.OtherActivity'),
                     good.replace('mCurrentFocus=Window{fixture-main u0 ' + ready.PACKAGE,
                                  'mCurrentFocus=Window{fixture-main u0 other.package'),
                     good.replace('mFocusedApp=ActivityRecord{fixture-target u0 ' + ready.PACKAGE,
                                  'mFocusedApp=ActivityRecord{fixture-target u0 other.package'),
                     good + good):
            self.assertFalse(ready.observe_dump(text)['ready'])

    def test_present_starting_surfaces_and_ambiguous_flags_are_not_ready(self):
        for extra in ('startingWindow=Window{fixture}', 'startingSurface=fixture',
                      'startingDisplayed=true', 'windows=[Splash Screen fixture]',
                      'startingWindow=null startingWindow=Window{fixture}', 'allDrawn=false'):
            text = drawn_fixture().replace('      state=RESUMED', '      ' + extra + '\n      state=RESUMED', 1)
            self.assertFalse(ready.observe_dump(text)['ready'], extra)

    def test_two_consecutive_same_activity_readbacks_are_required(self):
        clock = FakeClock()
        reads = iter([drawn_fixture(), FAILED_LAUNCH,
                      drawn_fixture().replace('fixture-target', 'fixture-new'),
                      drawn_fixture(), drawn_fixture()])
        report = ready.wait_for_ready(lambda timeout: next(reads), clock=clock.clock, sleep=clock.sleep)
        self.assertTrue(report['ready'])
        self.assertEqual(len(report['observations']), 5)
        self.assertEqual(report['consecutive_ready_readbacks'], 2)
        self.assertGreaterEqual(report['elapsed_ms'], 2000)
        serialized = json.dumps(report)
        self.assertNotIn('fixture-', serialized)
        self.assertNotIn('nexuslauncher', serialized)
        self.assertTrue(all(len(item['readback_sha256']) == 64 for item in report['observations']))

    def test_deadline_retains_safe_failure_flags(self):
        clock = FakeClock()
        timeouts = []
        def read(timeout):
            timeouts.append(timeout)
            return FAILED_LAUNCH
        report = ready.wait_for_ready(read, clock=clock.clock, sleep=clock.sleep)
        self.assertFalse(report['ready'])
        self.assertEqual(report['failure_code'], 'PLP_DRAWN_READINESS_NOT_REACHED')
        self.assertEqual(report['elapsed_ms'], 30000)
        self.assertLessEqual(len(report['observations']), 64)
        self.assertTrue(all(0 < timeout <= 5 for timeout in timeouts))
        self.assertFalse(report['observations'][-1]['flags']['reportedDrawn'])

    def test_adb_timeouts_and_failures_never_accept_previous_ready_observation(self):
        for effect, code in ((subprocess.TimeoutExpired('fixture-adb', 5), 'ACTIVITY_READ_TIMEOUT'),
                             (OSError('fixture-private-path'), 'ACTIVITY_READ_UNAVAILABLE'),
                             (subprocess.CompletedProcess([], 1, 'fixture-private-stdout', 'fixture-private-stderr'), 'ACTIVITY_READ_FAILED')):
            with self.subTest(code=code), patch.object(ready.subprocess, 'run') as run:
                if isinstance(effect, Exception):
                    run.side_effect = effect
                else:
                    run.return_value = effect
                clock = FakeClock()
                report = ready.wait_for_ready(lambda timeout: ready.read_activity('fixture-adb', 'fixture-serial', timeout),
                                             clock=clock.clock, sleep=clock.sleep)
                self.assertFalse(report['ready'])
                self.assertEqual(report['failure_code'], code)
                self.assertNotIn('fixture-', json.dumps(report))
                command = run.call_args.args[0]
                self.assertEqual(command[-4:], ['shell', 'dumpsys', 'activity', 'activities'])
                self.assertLessEqual(run.call_args.kwargs['timeout'], 5)

    def test_read_timeout_after_one_ready_cannot_pass(self):
        clock = FakeClock()
        calls = 0
        def read(timeout):
            nonlocal calls
            calls += 1
            if calls == 1:
                return drawn_fixture()
            raise ready.ReadinessFailure('ACTIVITY_READ_TIMEOUT')
        report = ready.wait_for_ready(read, clock=clock.clock, sleep=clock.sleep)
        self.assertFalse(report['ready'])
        self.assertEqual(report['failure_code'], 'ACTIVITY_READ_TIMEOUT')
        self.assertEqual(report['consecutive_ready_readbacks'], 1)


    def test_cli_persists_safe_nonready_report_and_fixed_failure(self):
        clock = FakeClock()
        report = ready.wait_for_ready(lambda timeout: FAILED_LAUNCH,
                                     clock=clock.clock, sleep=clock.sleep)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'readiness.json'
            arguments = ['wait_for_plp_android_ready.py', '--adb', 'fixture-adb',
                         '--serial', 'fixture-private-serial', '--output', str(output)]
            stderr = io.StringIO()
            with patch.object(ready.sys, 'argv', arguments), \
                    patch.object(ready, 'wait_for_ready', return_value=report), \
                    contextlib.redirect_stderr(stderr):
                self.assertEqual(ready.main(), 1)
            saved = json.loads(output.read_text())
            self.assertFalse(saved['ready'])
            self.assertFalse(saved['observations'][-1]['flags']['allDrawn'])
            self.assertEqual(stderr.getvalue().strip(), 'PLP_DRAWN_READINESS_NOT_REACHED')
            self.assertNotIn('fixture-', output.read_text())

    def test_workflow_drawn_checks_bound_capture_single_tap_and_restart(self):
        workflow = Path(__file__).resolve().parents[3] / '.github/workflows/plp-pandora-enterprise-android.yml'
        source = workflow.read_text()
        step = source.split('- name: Exercise installed PLP APK lifecycle and unauthenticated client flow', 1)[1]
        step = step.split('- name: Upload installed-app acceptance evidence', 1)[0]
        ordered = ['"$evidence/launch.png"',
                   'wait_for_drawn_ui "$evidence/launch-readiness.json"',
                   '"$evidence/sign-in.png"', 'capture_ui sign-in',
                   'wait_for_drawn_ui "$evidence/pre-submit-readiness.json"',
                   'adb_call shell input tap "$tap_x" "$tap_y"',
                   'capture_ui validation',
                   'wait_for_drawn_ui "$evidence/restart-readiness.json"',
                   '"$evidence/restart.png"', 'capture_ui restart']
        positions = [step.index(item) for item in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(step.count('adb_call shell input tap'), 1)
        self.assertNotIn('activity-launch.txt', step)


if __name__ == '__main__':
    unittest.main()
