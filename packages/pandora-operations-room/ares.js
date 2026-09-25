"use strict";
const path = require("node:path");
const { demand, integer, exactKeys, frozen } = require("./contracts");
// Returns argv, never a shell command. The host executor must check its durable lease before execFile.
function adbCommand(
	action,
	{
		serial,
		packageName = "com.banataosystems.pandora_mobile",
		artifactPath,
		workspaceRoot,
		adbPath,
		verifiedApk = false,
	} = {},
) {
	demand(
		typeof serial === "string" &&
			/^(emulator-\d{4,5}|[A-Za-z0-9_-]{4,100})$/.test(serial),
		"ADB_SERIAL_INVALID",
	);
	demand(
		["com.banataosystems.pandora_mobile"].includes(packageName),
		"PACKAGE_NOT_ALLOWLISTED",
	);
	exactKeys(action, [
		"kind",
		"x",
		"y",
		"x2",
		"y2",
		"durationMs",
		"text",
		"permission",
	]);
	const args = ["-s", serial];
	let destructive = false;
	switch (action.kind) {
		case "health":
			args.push("get-state");
			break;
		case "boot":
			args.push("shell", "getprop", "sys.boot_completed");
			break;
		case "abi":
			args.push("shell", "getprop", "ro.product.cpu.abilist");
			break;
		case "install": {
			demand(verifiedApk === true, "VERIFIED_APK_REQUIRED");
			demand(
				typeof workspaceRoot === "string" && typeof artifactPath === "string",
				"ARTIFACT_PATH_REQUIRED",
			);
			const root = path.win32.resolve(workspaceRoot),
				file = path.win32.resolve(artifactPath),
				rel = path.win32.relative(root, file);
			demand(
				rel !== "" &&
					!rel.startsWith("..") &&
					!path.win32.isAbsolute(rel) &&
					/\.apk$/i.test(file),
				"ARTIFACT_PATH_ESCAPE",
			);
			args.push("install", "-r", file);
			break;
		}
		case "launch":
			args.push(
				"shell",
				"monkey",
				"-p",
				packageName,
				"-c",
				"android.intent.category.LAUNCHER",
				"1",
			);
			break;
		case "force_stop":
			args.push("shell", "am", "force-stop", packageName);
			break;
		case "package":
			args.push("shell", "dumpsys", "package", packageName);
			break;
		case "crashes":
			args.push("logcat", "-b", "crash", "-d", "-t", "200");
			break;
		case "tap":
			integer(action.x, 0, 16384, "COORDINATE_INVALID");
			integer(action.y, 0, 16384, "COORDINATE_INVALID");
			args.push("shell", "input", "tap", String(action.x), String(action.y));
			break;
		case "swipe":
			for (const v of [action.x, action.y, action.x2, action.y2])
				integer(v, 0, 16384, "COORDINATE_INVALID");
			integer(action.durationMs, 1, 10000, "DURATION_INVALID");
			args.push(
				"shell",
				"input",
				"swipe",
				...[action.x, action.y, action.x2, action.y2, action.durationMs].map(
					String,
				),
			);
			break;
		case "type":
			demand(
				typeof action.text === "string" &&
					/^[a-zA-Z0-9 ._-]{1,200}$/.test(action.text),
				"ADB_TEXT_UNSAFE",
			);
			args.push("shell", "input", "text", action.text.replace(/ /g, "%s"));
			break;
		case "back":
			args.push("shell", "input", "keyevent", "KEYCODE_BACK");
			break;
		case "screenshot":
			args.push("exec-out", "screencap", "-p");
			break;
		case "clear_data":
			destructive = true;
			args.push("shell", "pm", "clear", packageName);
			break;
		default:
			throw new Error("ADB_ACTION_NOT_REGISTERED");
	}
	demand(
		typeof adbPath === "string" &&
			path.win32.isAbsolute(adbPath) &&
			path.win32.basename(adbPath).toLowerCase() === "adb.exe",
		"TRUSTED_ADB_PATH_REQUIRED",
	);
	return frozen({
		file: adbPath,
		args,
		options: {
			shell: false,
			timeout: action.kind === "install" ? 120000 : 15000,
			maxBuffer: action.kind === "screenshot" ? 16 * 1024 * 1024 : 1024 * 1024,
			windowsHide: true,
		},
		destructive,
		physicalDeviceVerified: false,
	});
}
function emulatorReadiness({
	hostReachable,
	adbState,
	bootCompleted,
	shellResponsive,
	guestAbi,
	apkAbi,
}) {
	const blockers = [];
	if (!hostReachable) blockers.push("host_unreachable");
	if (adbState !== "device") blockers.push("adb_not_ready");
	if (bootCompleted !== "1") blockers.push("boot_incomplete");
	if (shellResponsive !== true) blockers.push("shell_unresponsive");
	if (!Array.isArray(guestAbi) || !apkAbi || !guestAbi.includes(apkAbi))
		blockers.push("abi_unverified_or_incompatible");
	return frozen({
		ready: blockers.length === 0,
		blockers,
		physicalDeviceVerified: false,
	});
}
module.exports = { adbCommand, emulatorReadiness };
