# crud_supplychain.py
# Chương trình Unified CRUD Demo tương tác chéo VM1 <-> VM2 qua Radmin VPN
# Cấu trúc menu đơn giản, nhập liệu hoàn toàn động (không gán giá trị mặc định hiển thị)
# Hỗ trợ cấu trúc Schema mới trong schema_new.txt

import json
import pydgraph
import sys
from datetime import datetime

# Force stdout/stderr to utf-8 to handle Vietnamese characters in Windows Console
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

# Cấu hình IP và Port của các Alpha node trong mạng Radmin VPN của Máy 1 và Máy 2
NODE_VM1_ALPHA1 = "26.58.160.85:9080"
NODE_VM2_ALPHA2 = "26.181.76.80:9080"

def create_client(connection_str):
    """Khởi tạo Dgraph client stub từ chuỗi kết nối host:port"""
    client_stub = pydgraph.DgraphClientStub(connection_str)
    client = pydgraph.DgraphClient(client_stub)
    return client, client_stub

# --- UTILITY PRINTING FUNCTIONS ---

def print_all_customers(client):
    """Truy vấn và in ra danh sách khách hàng hiện có kèm thông tin địa lý"""
    query = """
    {
      customers(func: type(Customer)) {
        uid
        cus.Fname
        cus.street
        cus.segment
        cus.location {
          uid
          geo.city
          geo.state
          geo.country
        }
      }
    }
    """
    txn = client.txn(read_only=True)
    try:
        res = txn.query(query)
        data = json.loads(res.json).get('customers', [])
        print("\n--- DANH SÁCH KHÁCH HÀNG HIỆN TẠI ---")
        if not data:
            print("(Không có khách hàng nào)")
        for c in data:
            geo = c.get('cus.location')
            geo_str = "N/A"
            if geo:
                if isinstance(geo, list):
                    geo = geo[0] if geo else {}
                geo_parts = filter(None, [geo.get('geo.city'), geo.get('geo.state'), geo.get('geo.country')])
                geo_str = ", ".join(geo_parts) or "Trống"
            print(f"- UID: {c.get('uid')} | Tên: {c.get('cus.Fname')} | Địa chỉ: {c.get('cus.street', 'N/A')} | Phân khúc: {c.get('cus.segment', 'N/A')} | Địa lý: {geo_str}")
    except Exception as e:
        print(f"Lỗi khi lấy danh sách khách hàng: {e}")
    finally:
        txn.discard()

def print_all_products(client):
    """Truy vấn và in ra danh sách sản phẩm hiện có"""
    query = """
    {
      products(func: type(Product)) {
        uid
        prod.name
        prod.price
        prod.category {
          uid
          cate.name
        }
      }
    }
    """
    txn = client.txn(read_only=True)
    try:
        res = txn.query(query)
        data = json.loads(res.json).get('products', [])
        print("\n--- DANH SÁCH SẢN PHẨM HIỆN TẠI ---")
        if not data:
            print("(Không có sản phẩm nào)")
        for p in data:
            cat = p.get('prod.category', {})
            if isinstance(cat, list):
                cat = cat[0] if cat else {}
            print(f"- UID: {p.get('uid')} | Tên: {p.get('prod.name')} | Giá: {p.get('prod.price')} | Danh mục: {cat.get('cate.name', 'N/A')} ({cat.get('uid', 'N/A')})")
    except Exception as e:
        print(f"Lỗi khi lấy danh sách sản phẩm: {e}")
    finally:
        txn.discard()

def print_all_orders(client):
    """Truy vấn và in ra danh sách đơn hàng hiện có"""
    query = """
    {
      orders(func: type(Order)) {
        uid
        ord.date
        ord.status
        ord.customer {
          uid
          cus.Fname
        }
        ord.items {
          uid
          ordit.quantity
          ordit.product {
            uid
            prod.name
          }
        }
      }
    }
    """
    txn = client.txn(read_only=True)
    try:
        res = txn.query(query)
        data = json.loads(res.json).get('orders', [])
        print("\n--- DANH SÁCH ĐƠN HÀNG HIỆN TẠI ---")
        if not data:
            print("(Không có đơn hàng nào)")
        for o in data:
            cust = o.get('ord.customer', {})
            if isinstance(cust, list):
                cust = cust[0] if cust else {}
            items = o.get('ord.items', [])
            item_strs = []
            for it in items:
                prod = it.get('ordit.product', {})
                if isinstance(prod, list):
                    prod = prod[0] if prod else {}
                item_strs.append(f"{it.get('ordit.quantity')}x {prod.get('prod.name', 'N/A')} ({it.get('uid')})")
            print(f"- UID: {o.get('uid')} | Ngày: {o.get('ord.date')} | Trạng thái: {o.get('ord.status')} | Khách hàng: {cust.get('cus.Fname', 'N/A')} | Items: {', '.join(item_strs)}")
    except Exception as e:
        print(f"Lỗi khi lấy danh sách đơn hàng: {e}")
    finally:
        txn.discard()

def print_all_categories(client):
    """Truy vấn và in ra danh sách danh mục sản phẩm hiện có"""
    query = """
    {
      categories(func: type(Category)) {
        uid
        cate.name
      }
    }
    """
    txn = client.txn(read_only=True)
    try:
        res = txn.query(query)
        data = json.loads(res.json).get('categories', [])
        print("\n--- DANH SÁCH DANH MỤC HIỆN TẠI ---")
        if not data:
            print("(Không có danh mục nào)")
        for c in data:
            print(f"- UID: {c.get('uid')} | Tên: {c.get('cate.name')}")
    except Exception as e:
        print(f"Lỗi khi lấy danh sách danh mục: {e}")
    finally:
        txn.discard()


# ========================================================
# --- 1. CREATE OPERATIONS (THÊM DỮ LIỆU) ---
# ========================================================

def do_create(client):
    print("\n--- THAO TÁC: CREATE (THÊM DỮ LIỆU) ---")
    print("1. Thêm Đơn hàng mới (Order & OrderItem) cho khách hàng")
    print("2. Thêm Sản phẩm mới (Product) thuộc danh mục")
    print("3. Thêm Khách hàng mới (Customer) kèm thông tin địa lý (Geography)")
    choice = input("Nhập lựa chọn của bạn (1-3): ").strip()
    
    if choice == "1":
        print("\n[CREATE] Thêm đơn hàng mới")
        cus_name = input("- Nhập tên khách hàng: ").strip()
        prod_name = input("- Nhập tên sản phẩm muốn mua: ").strip()
        
        if not cus_name or not prod_name:
            print("❌ Lỗi: Tên khách hàng và sản phẩm không được để trống!")
            return
        
        # Bước 1: Kiểm tra khách hàng có tồn tại không
        check_user_query = """
        query checkUser($name: string) {
          user(func: eq(cus.Fname, $name)) {
            uid
            cus.Fname
          }
        }
        """
        txn = client.txn(read_only=True)
        try:
            res = txn.query(check_user_query, variables={'$name': cus_name})
            user_data = json.loads(res.json).get("user", [])
            if not user_data:
                print(f"❌ Lỗi: Không tìm thấy khách hàng '{cus_name}' trong hệ thống!")
                return
            customer_uid = user_data[0]["uid"]
            print(f"➔ Tìm thấy khách hàng '{cus_name}' với UID: {customer_uid}")
        finally:
            txn.discard()

        # Bước 2: Kiểm tra sản phẩm có tồn tại không
        check_prod_query = """
        query checkProd($name: string) {
          product(func: eq(prod.name, $name)) {
            uid
            prod.name
          }
        }
        """
        txn = client.txn(read_only=True)
        try:
            res = txn.query(check_prod_query, variables={'$name': prod_name})
            prod_data = json.loads(res.json).get("product", [])
            if not prod_data:
                print(f"❌ Lỗi: Không tìm thấy sản phẩm '{prod_name}'!")
                return
            product_uid = prod_data[0]["uid"]
            print(f"➔ Tìm thấy sản phẩm '{prod_name}' với UID: {product_uid}")
        finally:
            txn.discard()

        # Nhập các thông tin chi tiết đơn hàng
        qty_in = input("- Nhập số lượng mua: ").strip()
        try:
            ord_qty = int(qty_in) if qty_in else 1
        except ValueError:
            ord_qty = 1
            
        disc_in = input("- Nhập giảm giá %: ").strip()
        try:
            ord_disc = float(disc_in) if disc_in else 0.0
        except ValueError:
            ord_disc = 0.0
            
        ord_status = input("- Nhập trạng thái đơn hàng: ").strip()
        if not ord_status:
            ord_status = "PENDING_PAYMENT"

        # In danh sách đơn hàng trước khi thêm
        print_all_orders(client)

        # Bước 3: Tiến hành thêm đơn hàng mới lồng nhau
        mutation_data = {
            "uid": "_:new_order",
            "dgraph.type": "Order",
            "ord.date": datetime.utcnow().isoformat() + "Z",
            "ord.status": ord_status,
            "ord.customer": {"uid": customer_uid},
            "ord.items": [
                {
                    "uid": "_:new_item",
                    "dgraph.type": "OrderItem",
                    "ordit.quantity": ord_qty,
                    "ordit.discount": ord_disc,
                    "ordit.product": {"uid": product_uid}
                }
            ]
        }
        
        txn = client.txn()
        try:
            response = txn.mutate(set_obj=mutation_data)
            txn.commit()
            print("\n➔ [KẾT QUẢ] Thêm đơn hàng mới thành công!")
            print("Mã UIDs mới được Dgraph sinh ra:")
            for key, val in response.uids.items():
                print(f"  * {key} ➔ {val}")
        except Exception as e:
            print(f"❌ Thao tác chèn thất bại: {e}")
        finally:
            txn.discard()

        # In danh sách đơn hàng sau khi thêm
        print_all_orders(client)
        
    elif choice == "2":
        # Thêm sản phẩm mới thuộc danh mục
        print("\n[CREATE] Thêm sản phẩm mới thuộc danh mục")
        prod_name = input("- Nhập tên sản phẩm cần thêm: ").strip()
        price_in = input("- Nhập giá sản phẩm: ").strip()
        try:
            prod_price = float(price_in) if price_in else 0.0
        except ValueError:
            prod_price = 0.0
        cat_name = input("- Nhập tên danh mục sản phẩm: ").strip()

        if not prod_name or not cat_name:
            print("❌ Lỗi: Tên sản phẩm và danh mục không được để trống!")
            return

        # Lấy UID của category theo tên
        cat_query = """
        query getCat($name: string) {
          category(func: eq(cate.name, $name)) {
            uid
            cate.name
          }
        }
        """
        txn = client.txn(read_only=True)
        try:
            res = txn.query(cat_query, variables={'$name': cat_name})
            cats = json.loads(res.json).get('category', [])
            if not cats:
                print(f"❌ Không tìm thấy danh mục '{cat_name}'!")
                print("Đang tự động khởi tạo danh mục mới...")
                category_uid = None
            else:
                category_uid = cats[0]['uid']
                print(f"➔ Tìm thấy danh mục '{cat_name}' với UID: {category_uid}")
        finally:
            txn.discard()

        # In danh sách sản phẩm trước khi thêm
        print_all_products(client)

        # Thêm sản phẩm mới
        if category_uid:
            mutation_data = {
                "dgraph.type": "Product",
                "prod.name": prod_name,
                "prod.price": prod_price,
                "prod.category": {"uid": category_uid}
            }
        else:
            mutation_data = {
                "dgraph.type": "Product",
                "prod.name": prod_name,
                "prod.price": prod_price,
                "prod.category": {
                    "dgraph.type": "Category",
                    "cate.name": cat_name
                }
            }

        txn = client.txn()
        try:
            response = txn.mutate(set_obj=mutation_data)
            txn.commit()
            print("\n➔ [KẾT QUẢ] Thêm sản phẩm thành công!")
            for key, val in response.uids.items():
                print(f"  * {key} ➔ {val}")
        except Exception as e:
            print(f"❌ Thao tác chèn thất bại: {e}")
        finally:
            txn.discard()

        # In danh sách sản phẩm sau khi thêm
        print_all_products(client)
        
    elif choice == "3":
        # Thêm khách hàng mới kèm Geography
        print("\n[CREATE] Thêm Khách hàng mới")
        cus_name = input("- Nhập họ tên khách hàng: ").strip()
        cus_street = input("- Nhập địa chỉ đường phố: ").strip()
        cus_segment = input("- Nhập phân khúc (mặc định: Consumer): ").strip()
        if not cus_segment:
            cus_segment = "Consumer"
            
        cus_city = input("- Nhập thành phố (City, để trống nếu không có): ").strip()
        cus_state = input("- Nhập bang/tỉnh (State, để trống nếu không có): ").strip()
        cus_country = input("- Nhập quốc gia (Country, để trống nếu không có): ").strip()
        
        if not cus_name:
            print("❌ Lỗi: Tên khách hàng không được để trống!")
            return
            
        print_all_customers(client)
        
        mutation_data = {
            "dgraph.type": "Customer",
            "cus.Fname": cus_name,
            "cus.street": cus_street if cus_street else None,
            "cus.segment": cus_segment
        }
        mutation_data = {k: v for k, v in mutation_data.items() if v is not None}
        
        if cus_city or cus_state or cus_country:
            geo_node = {
                "uid": "_:new_geo",
                "dgraph.type": "Geography",
                "geo.city": cus_city if cus_city else None,
                "geo.state": cus_state if cus_state else None,
                "geo.country": cus_country if cus_country else None
            }
            geo_node = {k: v for k, v in geo_node.items() if v is not None}
            mutation_data["cus.location"] = geo_node
        
        txn = client.txn()
        try:
            response = txn.mutate(set_obj=mutation_data)
            txn.commit()
            print(f"\n➔ [KẾT QUẢ] Thêm khách hàng '{cus_name}' thành công!")
            for key, val in response.uids.items():
                print(f"  * UID cấp phát: {val}")
        except Exception as e:
            print(f"❌ Thao tác chèn thất bại: {e}")
        finally:
            txn.discard()
            
        print_all_customers(client)
    else:
        print("❌ Lựa chọn không hợp lệ!")


# ========================================================
# --- 2. READ OPERATIONS (TRUY VẦN DỮ LIỆU) ---
# ========================================================

def do_read(client):
    print("\n--- THAO TÁC: READ (TRUY VẦN DỮ LIỆU) ---")
    print("1. Truy vấn chi tiết đơn hàng của một Khách hàng")
    print("2. Truy vấn sản phẩm & Thống kê theo danh mục")
    print("3. Truy vấn hợp nhất Khách hàng từ cả 2 máy (VM1 + VM2)")
    choice = input("Nhập lựa chọn của bạn (1-3): ").strip()
    
    if choice == "1":
        cus_name = input("Nhập tên khách hàng cần tìm: ").strip()
        if not cus_name:
            print("❌ Lỗi: Tên khách hàng không được để trống!")
            return
            
        query = """
        query GetCustomerOrders($name: string) {
          result(func: eq(cus.Fname, $name)) {
            uid
            cus.Fname
            cus.street
            cus.segment
            cus.location {
              uid
              geo.city
              geo.state
              geo.country
            }
            ~ord.customer {
              uid
              ord.date
              ord.status
              ord.items {
                uid
                ordit.quantity
                ordit.discount
                ordit.product {
                  uid
                  prod.name
                  prod.price
                  prod.category {
                    uid
                    cate.name
                  }
                }
              }
            }
          }
        }
        """
        txn = client.txn(read_only=True)
        try:
            res = txn.query(query, variables={'$name': cus_name})
            data = json.loads(res.json)
            print(f"\n➔ [KẾT QUẢ TRUY VẦN] Thông tin đơn hàng của '{cus_name}':")
            print(json.dumps(data, indent=4, ensure_ascii=False))
        except Exception as e:
            print(f"❌ Truy vấn thất bại: {e}")
        finally:
            txn.discard()
            
    elif choice == "2":
        cat_name = input("Nhập tên danh mục để tìm kiếm: ").strip()
        if not cat_name:
            print("❌ Lỗi: Tên danh mục không được để trống!")
            return
            
        query = """
        query ProdsByCategory($tagName: string) {
          products(func: type(Product)) @filter(has(prod.category)) {
            uid
            prod.name
            prod.price
            prod.category @filter(eq(cate.name, $tagName)) {
              uid
              cate.name
            }
          }
          categories(func: type(Category)) {
            uid
            cate.name
            countProducts: count(~prod.category)
          }
        }
        """
        txn = client.txn(read_only=True)
        try:
            res = txn.query(query, variables={'$tagName': cat_name})
            data = json.loads(res.json)
            
            matching_prods = []
            for p in data.get('products', []):
                if p.get('prod.category'):
                    matching_prods.append(p)

            print(f"\nCác sản phẩm thuộc danh mục '{cat_name}':")
            if not matching_prods:
                print("  (Không tìm thấy sản phẩm nào)")
            for p in matching_prods:
                print(f"- UID: {p.get('uid')} | Tên: {p.get('prod.name')} | Giá: {p.get('prod.price')}")
                
            print("\nThống kê số lượng sản phẩm trên từng danh mục trong cụm:")
            for cat in data.get('categories', []):
                print(f"- Danh mục '{cat.get('cate.name')}': {cat.get('countProducts')} sản phẩm")
        except Exception as e:
            print(f"❌ Truy vấn thất bại: {e}")
        finally:
            txn.discard()
            
    elif choice == "3":
        # Hợp nhất khách hàng từ cả 2 máy
        print("\n[READ] Hợp nhất truy vấn khách hàng của hai máy...")
        client1, stub1 = None, None
        client2, stub2 = None, None
        
        try:
            client1, stub1 = create_client(NODE_VM1_ALPHA1)
            print(f"➔ Đã kết nối đến Máy 1: {NODE_VM1_ALPHA1}")
        except Exception as e:
            print(f"❌ Không thể kết nối đến Máy 1 ({NODE_VM1_ALPHA1}): {e}")
            
        try:
            client2, stub2 = create_client(NODE_VM2_ALPHA2)
            print(f"➔ Đã kết nối đến Máy 2: {NODE_VM2_ALPHA2}")
        except Exception as e:
            print(f"❌ Không thể kết nối đến Máy 2 ({NODE_VM2_ALPHA2}): {e}")

        if not client1 and not client2:
            print("❌ Không có kết nối Dgraph hoạt động. Không thể thực hiện truy vấn.")
            return

        dql_query = """
        {
          all_customers(func: type(Customer)) {
            uid
            cus.Fname
            cus.street
            cus.segment
            cus.location {
              uid
              geo.city
              geo.state
              geo.country
            }
          }
        }
        """
        combined_results = []
        
        for name, target_client, endpoint in [("Máy 1", client1, NODE_VM1_ALPHA1), ("Máy 2", client2, NODE_VM2_ALPHA2)]:
            if target_client:
                txn = target_client.txn(read_only=True)
                try:
                    res = txn.query(dql_query)
                    data = json.loads(res.json).get("all_customers", [])
                    print(f"  * Tìm thấy {len(data)} khách hàng từ {name}")
                    combined_results.extend(data)
                except Exception as ex:
                    print(f"  * Lỗi khi truy vấn {name}: {ex}")
                finally:
                    txn.discard()

        # Loại bỏ trùng lặp theo UID
        unique_results = []
        seen_uids = set()
        for item in combined_results:
            uid = item.get("uid")
            if uid and uid not in seen_uids:
                unique_results.append(item)
                seen_uids.add(uid)

        print(f"\n➔ [KẾT QUẢ TRUY VẦN HỢP NHẤT] Tổng cộng {len(unique_results)} khách hàng duy nhất:")
        print(json.dumps(unique_results, indent=4, ensure_ascii=False))

        if stub1: stub1.close()
        if stub2: stub2.close()
    else:
        print("❌ Lựa chọn không hợp lệ!")


# ========================================================
# --- 3. UPDATE OPERATIONS (CẬP NHẬT DỮ LIỆU) ---
# ========================================================

def do_update(client):
    print("\n--- THAO TÁC: UPDATE (SỬA DỮ LIỆU) ---")
    print("1. Cập nhật trạng thái Đơn hàng của khách hàng")
    print("2. Cập nhật địa chỉ, phân khúc & thông tin địa lý Khách hàng")
    choice = input("Nhập lựa chọn của bạn (1-2): ").strip()
    
    if choice == "1":
        cus_name = input("Nhập tên khách hàng cần tìm: ").strip()
        if not cus_name:
            print("❌ Lỗi: Tên khách hàng không được để trống!")
            return
            
        # Tìm thông tin đơn hàng của khách hàng trước để hiển thị
        query = """
        query getOrders($name: string) {
          user(func: eq(cus.Fname, $name)) {
            uid
            cus.Fname
            ~ord.customer {
              uid
              ord.status
            }
          }
        }
        """
        txn = client.txn(read_only=True)
        try:
            res = txn.query(query, variables={'$name': cus_name})
            users = json.loads(res.json).get('user', [])
            if not users or not users[0].get('~ord.customer'):
                print(f"❌ Không tìm thấy đơn hàng nào của khách hàng '{cus_name}' để cập nhật!")
                order_uid = input("Nhập UID đơn hàng cần cập nhật (nếu bạn biết): ").strip()
            else:
                orders = users[0]['~ord.customer']
                if not isinstance(orders, list):
                    orders = [orders]
                print(f"➔ Khách hàng '{cus_name}' đang có {len(orders)} đơn hàng:")
                for o in orders:
                    print(f"  * UID: {o['uid']} | Trạng thái hiện tại: {o['ord.status']}")
                order_uid = input("Nhập UID đơn hàng cần cập nhật từ danh sách trên: ").strip()
            
            new_status = input("Nhập trạng thái mới: ").strip()
            if not new_status:
                new_status = "COMPLETE"
        finally:
            txn.discard()

        if not order_uid:
            print("❌ Lỗi: UID đơn hàng không được để trống!")
            return

        print_all_orders(client)

        mutation_data = {
            "uid": order_uid,
            "ord.status": new_status
        }
        txn = client.txn()
        try:
            txn.mutate(set_obj=mutation_data)
            txn.commit()
            print(f"\n➔ [KẾT QUẢ] Cập nhật trạng thái đơn hàng {order_uid} thành '{new_status}' thành công!")
        except Exception as e:
            print(f"❌ Thao tác cập nhật thất bại: {e}")
        finally:
            txn.discard()

        print_all_orders(client)
        
    elif choice == "2":
        cus_name = input("Nhập tên khách hàng cần cập nhật: ").strip()
        if not cus_name:
            print("❌ Lỗi: Tên khách hàng không được để trống!")
            return
            
        query = """
        query getUser($name: string) {
          user(func: eq(cus.Fname, $name)) {
            uid
            cus.Fname
            cus.street
            cus.segment
            cus.location {
              uid
              geo.city
              geo.state
              geo.country
            }
          }
        }
        """
        txn = client.txn(read_only=True)
        try:
            res = txn.query(query, variables={'$name': cus_name})
            users = json.loads(res.json).get('user', [])
            if not users:
                print(f"❌ Không tìm thấy khách hàng với tên '{cus_name}'!")
                customer_uid = input("Nhập UID của Khách hàng cần sửa: ").strip()
                geo_uid = None
                old_city, old_state, old_country = "", "", ""
            else:
                user = users[0]
                customer_uid = user['uid']
                geo = user.get('cus.location', {})
                if isinstance(geo, list):
                    geo = geo[0] if geo else {}
                geo_uid = geo.get('uid')
                old_city = geo.get('geo.city', '')
                old_state = geo.get('geo.state', '')
                old_country = geo.get('geo.country', '')
                print(f"➔ Khách hàng hiện tại: UID: {customer_uid} | Địa chỉ cũ: {user.get('cus.street')} | Phân khúc cũ: {user.get('cus.segment')}")
                if geo_uid:
                    print(f"   Địa lý hiện tại (UID: {geo_uid}): City: {old_city} | State: {old_state} | Country: {old_country}")
            
            new_street = input("Nhập địa chỉ mới (để trống nếu giữ nguyên): ").strip()
            new_segment = input("Nhập phân khúc mới (để trống nếu giữ nguyên): ").strip()
            new_city = input("Nhập thành phố mới (để trống nếu giữ nguyên): ").strip()
            new_state = input("Nhập bang/tỉnh mới (để trống nếu giữ nguyên): ").strip()
            new_country = input("Nhập quốc gia mới (để trống nếu giữ nguyên): ").strip()
        finally:
            txn.discard()

        if not customer_uid:
            print("❌ Lỗi: UID khách hàng không được để trống!")
            return

        nquads = ""
        if new_street:
            nquads += f'<{customer_uid}> <cus.street> "{new_street}" .\n'
        if new_segment:
            nquads += f'<{customer_uid}> <cus.segment> "{new_segment}" .\n'
            
        if new_city or new_state or new_country:
            if geo_uid:
                # Cập nhật node Geography hiện tại
                if new_city:
                    nquads += f'<{geo_uid}> <geo.city> "{new_city}" .\n'
                if new_state:
                    nquads += f'<{geo_uid}> <geo.state> "{new_state}" .\n'
                if new_country:
                    nquads += f'<{geo_uid}> <geo.country> "{new_country}" .\n'
            else:
                # Tạo node Geography mới và liên kết
                nquads += f'<{customer_uid}> <cus.location> _:new_geo_node .\n'
                nquads += f'_:new_geo_node <dgraph.type> "Geography" .\n'
                if new_city:
                    nquads += f'_:new_geo_node <geo.city> "{new_city}" .\n'
                if new_state:
                    nquads += f'_:new_geo_node <geo.state> "{new_state}" .\n'
                if new_country:
                    nquads += f'_:new_geo_node <geo.country> "{new_country}" .\n'

        if not nquads:
            print("Không có thông tin nào thay đổi.")
            return

        txn = client.txn()
        try:
            txn.mutate(set_nquads=nquads)
            txn.commit()
            print(f"\n➔ [KẾT QUẢ] Cập nhật thành công thông tin khách hàng.")
        except Exception as e:
            print(f"❌ Thao tác cập nhật thất bại: {e}")
        finally:
            txn.discard()

        print_all_customers(client)
    else:
        print("❌ Lựa chọn không hợp lệ!")


# ========================================================
# --- 4. DELETE OPERATIONS (XÓA DỮ LIỆU) ---
# ========================================================

def do_delete(client):
    print("\n--- THAO TÁC: DELETE (XÓA DỮ LIỆU) ---")
    print("1. Xóa một OrderItem khỏi Order (Xóa liên kết)")
    print("2. Xóa Category và tất cả Product liên quan")
    print("3. Xóa hoàn toàn một đối tượng theo UID")
    choice = input("Nhập lựa chọn của bạn (1-3): ").strip()
    
    if choice == "1":
        print_all_orders(client)
        order_uid = input("Nhập UID Order muốn xóa item: ").strip()
        item_uid = input("Nhập UID OrderItem muốn xóa: ").strip()

        if not order_uid or not item_uid:
            print("❌ Lỗi: Vui lòng nhập đầy đủ UID của Order và OrderItem!")
            return

        nquad_delete = f"""
          <{order_uid}> <ord.items> <{item_uid}> .
          <{item_uid}> * * .
        """
        txn = client.txn()
        try:
            txn.mutate(del_nquads=nquad_delete)
            txn.commit()
            print(f"\n➔ [KẾT QUẢ] Đã xóa OrderItem '{item_uid}' ra khỏi Order '{order_uid}' thành công.")
        except Exception as e:
            print(f"❌ Thao tác xóa thất bại: {e}")
        finally:
            txn.discard()

        print_all_orders(client)
        
    elif choice == "2":
        print_all_categories(client)
        cat_name = input("Nhập tên danh mục muốn xóa: ").strip()
        if not cat_name:
            print("❌ Lỗi: Tên danh mục không được để trống!")
            return

        query = """
        query getCatAndProds($name: string) {
          category(func: eq(cate.name, $name)) {
            uid
            ~prod.category {
              uid
            }
          }
        }
        """
        txn = client.txn(read_only=True)
        try:
            res = txn.query(query, variables={'$name': cat_name})
            cats = json.loads(res.json).get('category', [])
            if not cats:
                print(f"❌ Không tìm thấy danh mục với tên '{cat_name}'")
                return
            
            category_uid = cats[0]['uid']
            products = cats[0].get('~prod.category', [])
            if not isinstance(products, list):
                products = [products]
            print(f"➔ Tìm thấy danh mục '{cat_name}' ({category_uid}) với {len(products)} sản phẩm liên quan.")
        finally:
            txn.discard()

        print_all_products(client)

        del_nquads = ""
        for prod in products:
            del_nquads += f"<{prod['uid']}> * * .\n"
        del_nquads += f"<{category_uid}> * * .\n"

        txn = client.txn()
        try:
            txn.mutate(del_nquads=del_nquads)
            txn.commit()
            print(f"\n➔ [KẾT QUẢ] Đã xóa thành công danh mục '{cat_name}' và {len(products)} sản phẩm liên quan.")
        except Exception as e:
            print(f"❌ Thao tác xóa thất bại: {e}")
        finally:
            txn.discard()

        print_all_products(client)
        print_all_categories(client)
        
    elif choice == "3":
        node_uid = input("Nhập UID đối tượng muốn xóa hoàn toàn: ").strip()
        if not node_uid:
            print("❌ Lỗi: UID không được để trống!")
            return

        txn = client.txn()
        try:
            txn.mutate(del_obj={"uid": node_uid})
            txn.commit()
            print(f"\n➔ [KẾT QUẢ] Đã xóa hoàn toàn nút {node_uid} thành công khỏi CSDL.")
        except Exception as e:
            print(f"❌ Thao tác xóa thất bại: {e}")
        finally:
            txn.discard()
    else:
        print("❌ Lựa chọn không hợp lệ!")


# ========================================================
# --- MAIN CONTROLLER LOOP ---
# ========================================================

def main():
    current_node = NODE_VM1_ALPHA1
    
    while True:
        print("\n" + "="*70)
        print(f"      CHƯƠNG TRÌNH DEMO CRUD DGRAPH PHÂN TÁN CHÉO VM")
        print(f"      [NODE KẾT NỐI HIỆN TẠI: {current_node}]")
        print("="*70)
        print(" 1. CREATE - Thêm dữ liệu (Đơn hàng / Sản phẩm / Khách hàng)")
        print(" 2. READ   - Truy vấn dữ liệu (Chi tiết / Thống kê / Hợp nhất)")
        print(" 3. UPDATE - Cập nhật dữ liệu (Trạng thái / Thông tin Khách hàng)")
        print(" 4. DELETE - Xóa dữ liệu (OrderItem / Category & Products / UID)")
        print(" 5. SWITCH - Thay đổi Dgraph Alpha Node kết nối (VM1 / VM2)")
        print(" 6. EXIT   - Thoát chương trình")
        print("="*70)
        
        option = input("Nhập lựa chọn của bạn (1-6): ").strip()
        
        if option == "6":
            print("\nĐang thoát chương trình. Hẹn gặp lại!")
            break
            
        elif option == "5":
            print("\n--- CHỌN NODE DGRAPH ALPHA ĐỂ KẾT NỐI ---")
            print(f"1. VM1 - Node Alpha 1 ({NODE_VM1_ALPHA1})")
            print(f"2. VM2 - Node Alpha 2 ({NODE_VM2_ALPHA2})")
            node_choice = input("Chọn node (1-2): ").strip()
            if node_choice == "1":
                current_node = NODE_VM1_ALPHA1
            elif node_choice == "2":
                current_node = NODE_VM2_ALPHA2
            else:
                print("Lựa chọn không hợp lệ. Giữ nguyên kết nối cũ.")
            print(f"\n➔ Đã chuyển đổi kết nối thành công tới: {current_node}")
            continue

        # Với các tùy chọn 1, 2, 3, 4: tạo kết nối tạm thời tới node được chọn
        client, client_stub = None, None
        try:
            client, client_stub = create_client(current_node)
            
            if option == "1":
                do_create(client)
            elif option == "2":
                do_read(client)
            elif option == "3":
                do_update(client)
            elif option == "4":
                do_delete(client)
            else:
                print("\nLựa chọn không hợp lệ, vui lòng nhập lại từ 1 đến 6!")
        except Exception as conn_err:
            print(f"\n➔ [LỖI GIAO TIẾP] Lỗi khi thực hiện trên node {current_node}: {conn_err}")
            print("Mẹo: Hãy kiểm tra xem máy ảo đã bật và container Alpha tương ứng có đang chạy không.")
        finally:
            if client_stub:
                client_stub.close()

if __name__ == "__main__":
    main()
