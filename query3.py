import pydgraph
import json

IP_MAY_1 = "26.58.160.85:9080"

# Sử dụng biến Argument ($customer_name)
AGGREGATE_QUERY = """
query user_history($customer_name: string) {
  data(func: eq(cus.Fname, $customer_name)) {
    cus.Fname
    cus.segment
    total_orders: count(~ord.customer)
    
    ~ord.customer {
      ord.date
      ord.items {
        ordit.product {
          prod.name
        }
      }
    }
  }
}
"""

def get_customer_stats(name_argument):
    client = pydgraph.DgraphClient(pydgraph.DgraphClientStub(IP_MAY_1))
    txn = client.txn(read_only=True)
    try:
        # Truyền tham số Argument từ Application vào Database
        variables = {'$customer_name': name_argument}
        res = txn.query(AGGREGATE_QUERY, variables=variables)
        
        data = json.loads(res.json).get('data', [])
        return data[0] if data else None
    finally:
        txn.discard()

if __name__ == "__main__":
    target_name = input("Nhập tên khách hàng: ").strip()
    print(f"\nMáy 2 đang gửi RPC truyền argument '{target_name}' sang máy 1...")
    
    result = get_customer_stats(target_name)
    
    if result:
        print(f"Khách hàng: {result.get('cus.Fname')}")
        print(f"Phân khúc: {result.get('cus.segment')}")
        print(f"Tổng số đơn hàng đã đặt: {result.get('total_orders')} đơn")
        print("Chi tiết:")
        print(json.dumps(result.get('~ord.customer', [])[:1], indent=2, ensure_ascii=False))
    else:
        print(f"\nKhông tìm thấy lịch sử giao dịch cho khách hàng '{target_name}' tại Máy 1.")