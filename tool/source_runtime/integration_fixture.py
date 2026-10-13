"""仅供集成检查，不由正式启动脚本或适配器注册导入。"""
import argparse
from datetime import datetime, timedelta, timezone
import json
import time
from adapters import TemplateAdapter, RuntimeFailure
from server import RuntimeServer


class FixtureAdapter(TemplateAdapter):
    adapter_id = "fixture"
    capabilities = ("search", "episodes", "resolve")

    def manifest(self):
        return {**super().manifest(), "implemented": True}

    def search(self, keyword, page, page_size, context):
        if keyword == "decrypt-error":
            raise RuntimeFailure("DECRYPT_ERROR")
        if keyword == "slow":
            for _ in range(300):
                context.check_active()
                time.sleep(0.01)
        if keyword == "empty":
            return {"data": [], "total": 0, "hasMore": False}
        return {"data": [{"name": f"仅测试电影 {page}", "url": f"fixture-content-{page}"}],
                "total": 2, "hasMore": page == 1}

    def episodes(self, source, context):
        context.check_active()
        return {"data": {"roads": [{"name": "测试原始线路", "episodes": [
            {"name": name, "url": f"https://source-runtime.playra.invalid/entries/{source}/{index}"}
            for index, name in enumerate(("第12集", "SP", "第11集"))]}]}}

    def resolve(self, episode_url, context):
        context.check_active()
        return {"data": {"url": "https://media.example.com/fixture.m3u8",
                "headers": {"Referer": "https://source.example.com/"}, "format": "hls",
                "expiresAt": (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat()}}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    with RuntimeServer(args.port, {"template": TemplateAdapter(), "fixture": FixtureAdapter()}) as server:
        print(json.dumps({"port": server.server_port}), flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
