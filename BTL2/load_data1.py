import pydgraph
import json
import time

CLUSTERS = [
    {"ip": "26.58.160.85:9080"},
    {"ip": "26.181.76.80:9080"}
]

def load_subset(cluster_ip, data_to_load):
    print(f"--- Đang nạp dữ liệu vào cụm: {cluster_ip} ---")

    client = pydgraph.DgraphClient(pydgraph.DgraphClientStub(cluster_ip))
    
    # CƠ CHẾ AUTO-RETRY (Thử lại tối đa 3 lần)
    max_retries = 3
    for attempt in range(max_retries):
        txn = client.txn() # Khởi tạo transaction MỚI cho mỗi lần thử
        try:
            txn.mutate(set_obj=data_to_load, commit_now=True)
            print(f"Thành công: Đã nạp dữ liệu vào {cluster_ip} (ở lần thử {attempt + 1})")
            break # Nạp thành công thì thoát vòng lặp
            
        except Exception as e:
            error_msg = str(e).lower()
            if "aborted" in error_msg:
                print(f"Giao dịch bị Abort tại {cluster_ip}. Đang thử lại ({attempt + 1}/{max_retries})...")
                time.sleep(2) # Chờ 2 giây để mạng ổn định rồi mới thử lại
            else:
                print(f"Lỗi cứng tại {cluster_ip}: {e}")
                break # Lỗi khác thì dừng luôn
        finally:
            txn.discard()

if __name__ == "__main__":
    with open('SupplyChainData_subset.json', 'r', encoding='utf-8') as f:
        full_data = json.load(f)
    
    part1 = full_data[:5]
    part2 = full_data[5:]
    
    load_subset("26.58.160.85:9080", part1)
    load_subset("26.181.76.80:9080", part2)
