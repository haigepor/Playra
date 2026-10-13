"""显式设备身份维护；不作为播放错误的自动重试分支。"""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile

from adapters import RuntimeContext
from miomedia_adapter import MioMediaAdapter, MioMediaSdk
from vendor.miomedia import Client


def replace_identity(identity_path, *, base_url=None, session_config=None):
    path = Path(identity_path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.new-device-', dir=path.parent)
    os.close(fd)
    scratch = Path(name)
    original = path.read_bytes() if path.exists() else None
    try:
        client = Client(base_url=base_url, session_config=session_config)
        client.save_identity(scratch)
        sdk = MioMediaSdk(scratch, base_url=base_url, session_config=session_config)
        sdk._ensure_session(RuntimeContext(20000))
        if original is not None:
            backup = path.with_name(f'device-before-{datetime.now().strftime("%Y%m%d-%H%M%S-%f")}.json')
            backup.write_bytes(original)
        # 校验成功才替换；失败时原身份及会话材料保持原样。
        os.replace(scratch, path)
        return {'status':'PASS','handshakeVerified':True,
                'identityChanged':original is None or hashlib.sha256(original).digest()!=hashlib.sha256(path.read_bytes()).digest()}
    finally:
        scratch.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='先停止算法服务；显式更新身份并完成会话初始化，无需 Android pm clear。')
    parser.add_argument('--replace', action='store_true', required=True)
    args = parser.parse_args()
    configured = MioMediaAdapter().sdk
    print(json.dumps(replace_identity(configured.identity_path, base_url=configured.base_url,
                                     session_config=configured.session_config)))
