"""维护者登记的适配器；HTTP 请求不能指定模块、脚本或命令。"""
from dataclasses import dataclass, field
from threading import Event
from time import monotonic


class RuntimeFailure(Exception):
    def __init__(self, code, status=502):
        self.code, self.status = code, status
        super().__init__(code)


@dataclass
class RuntimeContext:
    timeout_ms: int
    cancelled: Event = field(default_factory=Event)
    started: float = field(default_factory=monotonic)

    def check_active(self):
        if self.cancelled.is_set():
            raise RuntimeFailure("CANCELLED", 409)
        if (monotonic() - self.started) * 1000 >= self.timeout_ms:
            raise RuntimeFailure("TIMEOUT", 504)


class TemplateAdapter:
    adapter_id = "template"
    version = "0.1.0"
    domains = ("screen",)
    capabilities = ()

    def manifest(self):
        return {"id": self.adapter_id, "version": self.version,
                "domains": list(self.domains),
                "capabilities": list(self.capabilities), "implemented": False}

    def search(self, keyword, page, page_size, context):
        context.check_active()
        raise RuntimeFailure("UNSUPPORTED", 422)

    def episodes(self, source, context):
        context.check_active()
        raise RuntimeFailure("UNSUPPORTED", 422)

    def resolve(self, episode_url, context):
        context.check_active()
        raise RuntimeFailure("UNSUPPORTED", 422)

    # 接入时在适配器内实现签名/解密，不将密钥放入规则 JSON。
    def sign_request(self, parameters, context):
        context.check_active()
        raise RuntimeFailure("UNSUPPORTED", 422)

    def decode_response(self, payload, context):
        context.check_active()
        raise RuntimeFailure("UNSUPPORTED", 422)


def registered_adapters():
    # 后续显式添加受维护的实例；不自动导入用户上传的 Python 文件。
    adapter = TemplateAdapter()
    # SDK 只登记受限操作；健康/清单不初始化设备或发起上游请求。
    from miomedia_adapter import MioMediaAdapter
    miomedia = MioMediaAdapter()
    from anifive_adapter import registered_anifive
    return {adapter.adapter_id: adapter, miomedia.adapter_id: miomedia, **registered_anifive()}
