#!/usr/bin/env python3
"""Fail-closed verifier for Pandora Android physical-device acceptance candidates."""
from __future__ import annotations
import argparse, hashlib, json, re, subprocess, sys
from pathlib import Path
from typing import Mapping, Sequence
EXPECTED_PACKAGE = "com.banataosystems.pandora_mobile"
FALSE_GATES = ("physical_device_verified","wifi_journey_verified","mobile_data_journey_verified","authenticated_owner_journey_verified","network_switch_verified","rollback_verified")
SENSITIVE_PERMISSION_RE = re.compile(r"ACCESS_(?:FINE|COARSE|BACKGROUND)_LOCATION|READ_CONTACTS|WRITE_CONTACTS|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_|CAMERA|RECORD_AUDIO|BLUETOOTH_(?:SCAN|CONNECT|ADVERTISE)|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW", re.IGNORECASE)
class VerificationError(RuntimeError): pass
def sha256_file(path: Path) -> str:
    digest=hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024*1024), b""): digest.update(chunk)
    return digest.hexdigest()
def parse_manifest(path: Path) -> dict[str,str]:
    values={}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line=raw_line.strip()
        if not line or line.startswith("#"): continue
        if "=" not in line: raise VerificationError(f"invalid manifest line: {raw_line!r}")
        key,value=line.split("=",1); key=key.strip()
        if not key or key in values: raise VerificationError(f"invalid or duplicate manifest key: {key!r}")
        values[key]=value.strip()
    return values
def require_manifest_binding(manifest: Mapping[str,str], *, source_sha:str, apk_sha256:str, package_name:str, app_version:str)->None:
    if not re.fullmatch(r"[0-9a-f]{40}",source_sha): raise VerificationError("expected source SHA must be lowercase 40-hex")
    checks=(("source_sha",source_sha,"source SHA"),("apk_sha256",apk_sha256,"APK SHA-256"),("android_package",package_name,"Android package"),("app_version",app_version,"app version"))
    for key,expected,label in checks:
        if manifest.get(key)!=expected: raise VerificationError(f"manifest {label} does not match candidate")
    if manifest.get("artifact_class")!="validation-candidate": raise VerificationError("candidate is not an exact-source validation artifact")
    if manifest.get("production_release")!="false": raise VerificationError("validation manifest must not self-assert production release")
    for key in FALSE_GATES:
        if manifest.get(key)!="false": raise VerificationError(f"CI manifest must leave {key}=false until external proof")
def run_checked(command: Sequence[str])->str:
    try:
        completed=subprocess.run(list(command),check=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    except (OSError,subprocess.CalledProcessError) as error:
        output=getattr(error,"stdout",None) or str(error); raise VerificationError(f"command failed: {' '.join(command)}\n{output}") from error
    return completed.stdout
def parse_badging(text:str)->tuple[str,str,str]:
    package=re.search(r"package: name='([^']+)'",text); version_code=re.search(r"versionCode='([^']+)'",text); version_name=re.search(r"versionName='([^']+)'",text)
    if not package or not version_code or not version_name: raise VerificationError("aapt badging is missing package/version identity")
    return package.group(1),version_name.group(1),version_code.group(1)
def require_safe_permissions(permissions_text:str)->None:
    match=SENSITIVE_PERMISSION_RE.search(permissions_text)
    if match: raise VerificationError(f"unexpected sensitive Android permission detected: {match.group(0)}")
def signer_is_debug(signing_text:str)->bool:
    lowered=signing_text.lower(); return "android debug" in lowered or "cn=android debug" in lowered
def parse_signer_sha256(signing_text:str)->str:
    match=re.search(r"Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F:]{64,95})",signing_text)
    if not match: raise VerificationError("apksigner output is missing signer certificate SHA-256 digest")
    normalized=match.group(1).replace(":","").lower()
    if not re.fullmatch(r"[0-9a-f]{64}",normalized): raise VerificationError("apksigner certificate SHA-256 digest is malformed")
    return normalized
def require_expected_production_signer(signing_text:str, expected_sha256:str|None)->str:
    if not expected_sha256: raise VerificationError("production signer acceptance requires --expected-signer-sha256")
    normalized=expected_sha256.replace(":","").lower()
    if not re.fullmatch(r"[0-9a-f]{64}",normalized): raise VerificationError("expected signer SHA-256 must be 64 hex characters")
    actual=parse_signer_sha256(signing_text)
    if actual!=normalized: raise VerificationError("APK signer certificate SHA-256 does not match expected production signer")
    return actual
def adb_prefix(adb:str,serial:str|None)->list[str]:
    return [adb,"-s",serial] if serial else [adb]
def smoke_device(adb:str,serial:str|None,apk:Path,package_name:str)->dict[str,bool]:
    prefix=adb_prefix(adb,serial)
    if run_checked([*prefix,"get-state"]).strip()!="device": raise VerificationError("adb target is not in device state")
    run_checked([*prefix,"install","-r",str(apk)])
    if not run_checked([*prefix,"shell","pm","path",package_name]).strip().startswith("package:"): raise VerificationError("installed package cannot be resolved on device")
    launch=[*prefix,"shell","monkey","-p",package_name,"-c","android.intent.category.LAUNCHER","1"]
    run_checked(launch)
    if not run_checked([*prefix,"shell","pidof",package_name]).strip(): raise VerificationError("package did not remain launched after first start")
    run_checked([*prefix,"shell","am","force-stop",package_name]); run_checked(launch)
    if not run_checked([*prefix,"shell","pidof",package_name]).strip(): raise VerificationError("package did not relaunch after force-stop")
    return {"adb_device_online":True,"install_verified":True,"launch_verified":True,"force_stop_relaunch_verified":True,"device_smoke_verified":True}
def main()->int:
    parser=argparse.ArgumentParser(); parser.add_argument("--apk",required=True,type=Path); parser.add_argument("--manifest",required=True,type=Path); parser.add_argument("--expected-source-sha",required=True); parser.add_argument("--aapt",default="aapt"); parser.add_argument("--apksigner",default="apksigner"); parser.add_argument("--adb",default="adb"); parser.add_argument("--serial"); parser.add_argument("--smoke-device",action="store_true"); parser.add_argument("--require-production-signer",action="store_true"); parser.add_argument("--expected-signer-sha256"); args=parser.parse_args()
    if not args.apk.is_file() or not args.manifest.is_file(): raise VerificationError("APK and exact-source manifest must both exist")
    manifest=parse_manifest(args.manifest); apk_sha=sha256_file(args.apk); app_version=manifest.get("app_version","")
    require_manifest_binding(manifest,source_sha=args.expected_source_sha,apk_sha256=apk_sha,package_name=EXPECTED_PACKAGE,app_version=app_version)
    package_name,version_name,version_code=parse_badging(run_checked([args.aapt,"dump","badging",str(args.apk)]))
    if package_name!=EXPECTED_PACKAGE: raise VerificationError(f"unexpected Android package: {package_name}")
    expected_version_name=app_version.split("+",1)[0]; expected_version_code=app_version.split("+",1)[1] if "+" in app_version else ""
    if version_name!=expected_version_name or version_code!=expected_version_code: raise VerificationError("APK version identity does not match exact-source manifest")
    require_safe_permissions(run_checked([args.aapt,"dump","permissions",str(args.apk)]))
    signing=run_checked([args.apksigner,"verify","--verbose","--print-certs",str(args.apk)]); debug_signer=signer_is_debug(signing)
    signer_sha256=parse_signer_sha256(signing)
    if args.require_production_signer:
        if debug_signer: raise VerificationError("production acceptance cannot use the Android debug signer")
        signer_sha256=require_expected_production_signer(signing,args.expected_signer_sha256)
    evidence={"source_sha":args.expected_source_sha,"apk_sha256":apk_sha,"android_package":package_name,"version_name":version_name,"version_code":version_code,"permissions_verified":True,"debug_signer":debug_signer,"signer_sha256":signer_sha256,"manifest_bound":True,"device_smoke_verified":False,"physical_device_verified":False,"wifi_journey_verified":False,"mobile_data_journey_verified":False,"authenticated_owner_journey_verified":False,"network_switch_verified":False,"rollback_verified":False}
    if args.smoke_device: evidence.update(smoke_device(args.adb,args.serial,args.apk,package_name))
    print(json.dumps(evidence,sort_keys=True)); return 0
if __name__=="__main__":
    try: raise SystemExit(main())
    except VerificationError as error: print(f"PHYSICAL_ANDROID_ACCEPTANCE_FAIL: {error}",file=sys.stderr); raise SystemExit(2)
