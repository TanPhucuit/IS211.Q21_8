import pydgraph
import json

# Cấu hình IP được ẩn đi, người dùng hàm không cần biết (Location Transparency)
TARGET_NODE = "26.181.76.80:9080"

# Truy vấn có điều kiện lọc @filter trên các node con (OrderItem)
FILTER_QUERY = """
{
  q(func: has(ord.date)) {
    ord.date
    ord.status
    ord.customer {
      cus.Fname
    }
    # Chỉ lấy các mặt hàng có mức giảm giá > 10.0
    ord.items @filter(gt(ordit.discount, 10.0)) {
      ordit.quantity
      ordit.discount
      ordit.product {
        prod.name
        prod.price
      }
    }
  }
}
"""

def get_discounted_orders_transparently():
    client = pydgraph.DgraphClient(pydgraph.DgraphClientStub(TARGET_NODE))
    txn = client.txn(read_only=True)
    
    try:
        res = txn.query(FILTER_QUERY)
        data = json.loads(res.json).get('q', [])
        
        # Loại bỏ các đơn hàng rỗng
        valid_orders = [o for o in data if len(o.get('ord.items', [])) > 0]
        return valid_orders
        
    except Exception as e:
        print(f"Lỗi hệ thống ngầm: {e}")
        return []
    finally:
        txn.discard()

if __name__ == "__main__":
    ket_qua = get_discounted_orders_transparently()
    
    if ket_qua:
        print(f"Tìm thấy {len(ket_qua)} đơn hàng có mặt hàng giảm giá > 10.0:")
        print(json.dumps(ket_qua[:2], indent=2, ensure_ascii=False)) # In 2 kết quả mẫu
    else:
        print("Không có đơn hàng nào thỏa mãn điều kiện.")