"""纯标准库 SDK 加速版对照：同一数据与真实响应，密钥仅驻留内存。"""
import argparse
import gc
import importlib.util
import json
from pathlib import Path
import platform
import statistics
import time

from vendor.miomedia import Client, transport
from vendor.miomedia import suite


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def measure_pair(old, new, expected, repeats):
    samples = {'old': [], 'new': []}
    cpu = {'old': [], 'new': []}
    for i in range(repeats):
        for name, action in ([('old', old), ('new', new)] if i % 2 == 0 else [('new', new), ('old', old)]):
            started = time.perf_counter()
            cpu_start = time.process_time()
            result = action()
            cpu[name].append((time.process_time()-cpu_start)*1000)
            samples[name].append((time.perf_counter()-started)*1000)
            assert result == expected
    old_ms, new_ms = statistics.median(samples['old']), statistics.median(samples['new'])
    return {'oldMs': round(old_ms, 3), 'newMs': round(new_ms, 3),
            'speedup': round(old_ms/new_ms, 2), 'equal': True,
            'oldCpuMs': round(statistics.median(cpu['old']), 3),
            'newCpuMs': round(statistics.median(cpu['new']), 3),
            'samples': samples}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--old-suite', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--bytes', type=int, default=447726)
    parser.add_argument('--identity', default=str(Path(__file__).resolve().parents[2]/'.dart_tool/miomedia/device.json'))
    args = parser.parse_args()
    assert 1 <= args.repeats <= 7 and 1 <= args.bytes <= 1024*1024
    old = load_module('benchmark_old_suite', Path(args.old_suite).resolve())
    old.HERE = str(Path(suite.__file__).parent)
    result = {'python': platform.python_version(), 'repeats': args.repeats,
              'plainBytes': args.bytes, 'aggregation': 'median', 'primitives': []}
    data = bytes((i*37+11)%256 for i in range(args.bytes))
    gc.disable()
    try:
        for algo, key_size in ((1,8),(2,16),(3,0),(4,16),(5,44),(6,16)):
            key = bytes(range(key_size))
            ciphertext = suite.suite_encrypt(algo, key, data)
            # 一次热身检查，与 ECSM 多块共用调度的实际使用方式一致。
            assert suite.suite_decrypt(algo, key, ciphertext) == data
            row = {'algo':'M%d' % algo, **measure_pair(
                lambda: old.suite_decrypt(algo,key,ciphertext),
                lambda: suite.suite_decrypt(algo,key,ciphertext), data, args.repeats)}
            result['primitives'].append(row)
            print('%s old=%.3fms new=%.3fms speedup=%.2fx equal=True' %
                  (row['algo'],row['oldMs'],row['newMs'],row['speedup']), flush=True)
        client = Client.load_identity(args.identity, timeout=20)
        status, response = client.handshake()
        assert status == 200 and response['data']['deviceSecret'] == client.device_secret
        captured = {}
        original_post = client._post
        def post(path, body, headers):
            start = time.perf_counter()
            answer = original_post(path,body,headers)
            if path == '/video/modules':
                captured['wire'] = answer[1]
                captured['networkMs'] = (time.perf_counter()-start)*1000
            return answer
        client._post = post
        start = time.perf_counter()
        status, response = client.request('/video/modules', {'categoryId':'0','pageIndex':1,'pageSize':20})
        elapsed = (time.perf_counter()-start)*1000
        assert status == 200 and response.get('success') is True
        secret, wire = client.device_secret.encode('ascii'), captured['wire']
        reference = transport.decrypt_v3(secret,wire)
        slower = load_module('vendor.miomedia.benchmark_old_transport', transport.__file__)
        slower.suite_decrypt = old.suite_decrypt
        header = transport.parse_wire(wire,secret)
        result['realResponse'] = {
            'endpoint':'/video/modules', 'categoryId':'0', 'wireBytes':len(wire),
            'plainBytes':len(reference), 'flag':header['flag'], 'chain':header['mcs'],
            'networkMs':round(captured['networkMs'],3), 'newSdkTotalMs':round(elapsed,3),
            **measure_pair(lambda: slower.decrypt_v3(secret,wire),
                           lambda: transport.decrypt_v3(secret,wire), reference, args.repeats)}
        row = result['realResponse']
        print('REAL modules old=%.3fms new=%.3fms speedup=%.2fx network=%.3fms SDK_total=%.3fms bytes=%d equal=True' %
              (row['oldMs'],row['newMs'],row['speedup'],row['networkMs'],row['newSdkTotalMs'],row['plainBytes']), flush=True)
    finally:
        gc.enable()
    # 不写响应密文、会话密钥、设备身份、请求签名或内部配置。
    Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('BENCHMARK ALL PASS',flush=True)


if __name__ == '__main__':
    main()
