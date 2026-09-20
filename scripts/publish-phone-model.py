#!/usr/bin/env python3
"""GitHub-hosted distribution. Credentials stay in memory and never print."""
import base64
import hashlib
import json
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODEL = json.loads((ROOT / "models/phone/manifest.json").read_text())
ENDPOINT = "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-model-publisher"


def request(url, *, method="GET", headers=None, data=None, timeout=60):
    return urllib.request.urlopen(urllib.request.Request(
        url, data=data, method=method, headers=headers or {}), timeout=timeout)


def publisher(action, **fields):
    oidc_url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=pandora-model-publisher"
    with request(oidc_url, headers={
        "Authorization": "Bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]
    }) as response:
        token = json.load(response)["value"]
    with request(ENDPOINT, method="POST", headers={
        "Authorization": "Bearer " + token, "Content-Type": "application/json"
    }, data=json.dumps({"action": action, **fields}).encode()) as response:
        return json.load(response)


def verify_stream(url, destination=None):
    count, digest = 0, hashlib.sha256()
    with request(url, timeout=120) as response:
        if response.status != 200:
            raise RuntimeError("model_download_status")
        stream = open(destination, "wb") if destination else None
        try:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                count += len(chunk)
                if count > MODEL["bytes"]:
                    raise RuntimeError("model_oversize")
                digest.update(chunk)
                if stream:
                    stream.write(chunk)
        finally:
            if stream:
                stream.close()
    if count != MODEL["bytes"] or digest.hexdigest() != MODEL["sha256"]:
        raise RuntimeError("model_integrity")
    return count, digest.hexdigest()


def main():
    grant = publisher("grant")
    metadata = {
        "bucketName": grant["bucket"], "objectName": grant["object"],
        "contentType": "application/octet-stream", "cacheControl": "31536000",
    }
    tus_headers = {
        "Tus-Resumable": "1.0.0", "x-signature": grant["token"],
        "Upload-Length": str(MODEL["bytes"]),
        "Upload-Metadata": ",".join(
            key + " " + base64.b64encode(value.encode()).decode()
            for key, value in metadata.items()
        ),
    }
    # Prove Storage accepts this size before downloading 2 GB upstream.
    try:
        with request(grant["endpoint"], method="POST", headers=tus_headers, data=b"") as response:
            location = urllib.parse.urljoin(grant["endpoint"], response.headers["Location"])
    except urllib.error.HTTPError as error:
        print("STORAGE_UPLOAD_ADMISSION_FAILED http_status=" + str(error.code))
        print("Configured model bytes=" + str(MODEL["bytes"]) +
              ". Confirm the project's Storage global file limit and plan.")
        return 20
    location_url = urllib.parse.urlparse(location)
    if location_url.scheme != "https" or location_url.hostname != urllib.parse.urlparse(grant["endpoint"]).hostname:
        raise RuntimeError("upload_host")
    path = pathlib.Path(os.environ["RUNNER_TEMP"]) / "pandora-distribution.gguf"
    verify_stream(MODEL["upstream"], path)
    offset, chunk_size = 0, 6 * 1024 * 1024
    with path.open("rb") as stream:
        while offset < MODEL["bytes"]:
            stream.seek(offset)
            chunk = stream.read(chunk_size)
            expected = offset + len(chunk)
            try:
                with request(location, method="PATCH", headers={
                    "Tus-Resumable":"1.0.0", "x-signature":grant["token"],
                    "Upload-Offset":str(offset), "Content-Type":"application/offset+octet-stream",
                }, data=chunk, timeout=120) as response:
                    new_offset = int(response.headers["Upload-Offset"])
                    if new_offset != expected:
                        raise RuntimeError("upload_offset")
                    offset = new_offset
            except (urllib.error.URLError, TimeoutError):
                # Reconcile ambiguous writes before one bounded retry.
                with request(location, method="HEAD", headers={
                    "Tus-Resumable":"1.0.0", "x-signature":grant["token"],
                }) as response:
                    server_offset = int(response.headers["Upload-Offset"])
                if not offset <= server_offset <= expected:
                    raise RuntimeError("upload_resume_offset")
                stream.seek(server_offset)
                remaining = stream.read(expected - server_offset)
                if remaining:
                    with request(location, method="PATCH", headers={
                        "Tus-Resumable":"1.0.0", "x-signature":grant["token"],
                        "Upload-Offset":str(server_offset),
                        "Content-Type":"application/offset+octet-stream",
                    }, data=remaining, timeout=120) as response:
                        offset = int(response.headers["Upload-Offset"])
                    if offset != expected:
                        raise RuntimeError("upload_retry_offset")
                else:
                    offset = server_offset
    readback = publisher("readback")
    size, digest = verify_stream(readback["downloadUrl"])
    with request(readback["downloadUrl"], headers={"Range":"bytes=1024-2047"}) as response:
        if response.status != 206 or response.headers.get("Content-Range") != (
                "bytes 1024-2047/" + str(MODEL["bytes"])):
            raise RuntimeError("storage_range")
        remote = response.read()
    with path.open("rb") as stream:
        stream.seek(1024)
        if remote != stream.read(1024):
            raise RuntimeError("storage_range_bytes")
    result = publisher("complete", bytes=size, sha256=digest, rangeVerified=True)
    if result.get("recorded") is not True:
        raise RuntimeError("distribution_receipt")
    print(json.dumps({"distributionVerified":True,"bytes":size,"sha256":digest,
                      "physicalPhoneVerified":False}))
    path.unlink()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("DISTRIBUTION_FAILED class=" + type(error).__name__)
        sys.exit(1)
