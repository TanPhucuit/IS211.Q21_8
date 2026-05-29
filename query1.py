import pydgraph
import json

# Cấu hình IP ẩn bên trong hệ thống
IP_MAY_1 = "26.58.160.85:9080"
IP_MAY_2 = "26.181.76.80:9080"

DQL_QUERY = """
{
  all_customers(func: type(Customer)) {
    uid
    cus.Fname
    cus.segment
  }
}
"""

def execute_single_node(ip_address):
    # Khởi tạo kết nối gRPC tới từng Node
    client = pydgraph.DgraphClient(pydgraph.DgraphClientStub(ip_address))
    txn = client.txn(read_only=True)
    try:
        res = txn.query(DQL_QUERY)
        return json.loads(res.json).get('all_customers', [])
    except Exception:
        return []
    finally:
        txn.discard()

def get_all_customers_transparently():
    # Lấy dữ liệu song song từ các máy
    data_m1 = execute_single_node(IP_MAY_1)
    data_m2 = execute_single_node(IP_MAY_2)
    
    # Thực hiện phép UNION và loại trùng lặp
    combined_results = data_m1 + data_m2
    unique_customers = []
    seen_uids = set()
    
    # Loại bỏ trùng lặp bằng UID
    for customer in combined_results:
        uid = customer.get("uid")
        if uid and uid not in seen_uids:
            unique_customers.append(customer)
            seen_uids.add(uid)
            
    return unique_customers

if __name__ == "__main__":
    ket_qua = get_all_customers_transparently()
    
    print(f"\n=> Tìm thấy tổng cộng {len(ket_qua)} khách hàng toàn hệ thống:")
    print(json.dumps(ket_qua[:10], indent=2, ensure_ascii=False))