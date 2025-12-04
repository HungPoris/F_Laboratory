SET search_path = iamservice_db, public;
INSERT INTO roles (role_id, role_code, role_name, role_description, is_system_role, is_active, created_at)
VALUES
    ('d24c97cb-ead8-447c-8318-4631fdc928a2','ADMIN','Administrator','Full system administration',TRUE,TRUE,now()),
    ('5d6c50ef-851b-4ea8-985b-2a94bea662c8','LAB_MANAGER','Lab Manager','Manage operations & reports',TRUE,TRUE,now()),
    ('cc49e2f1-cdb2-42bd-9776-b641a22529bf','LAB_TECH','Lab Technician','Run instruments & validate results',FALSE,TRUE,now()),
    ('e73c5b55-62ea-4ac7-972c-c461c2d52b2f','LAB_USER','Lab User','Standard lab staff',FALSE,TRUE,now()),
    ('df87d5fc-0380-4b85-812e-d433bf6ab91a','SERVICE','Service','Internal system operations & automation',FALSE,TRUE,now()),
    ('427aec7d-b534-4d8a-a450-dc99419b4503','USER','Normal User','Patient portal read-only',FALSE,TRUE,now()),
    ('a3224f61-bfdf-4657-8cbf-a85327f588cb','CUSTOM','Custom','Blank role for ad-hoc permissions',FALSE,TRUE,now())
    ON CONFLICT (role_code) DO NOTHING;
INSERT INTO privileges (privilege_id, privilege_code, privilege_name, privilege_description, privilege_category, created_at)
VALUES
    ('77cb55f9-c0de-4887-9bbe-3192e0110b48','system.read_only','Read-only','Chỉ được xem Patient Test Orders và kết quả của chúng.','SYSTEM',now()),
    ('3de0222f-006a-4bb5-b579-53113f15a455','test_order.create','Create Test order','Tạo mới patient test order.','TEST_ORDER',now()),
    ('afedd297-90a6-4301-a948-760abfff586d','test_order.modify','Modify Test order','Chỉnh sửa thông tin patient test order.','TEST_ORDER',now()),
    ('26028ba2-9b3d-49d2-930a-50a4d3f7c6e1','test_order.delete','Delete Test order','Xoá patient test order.','TEST_ORDER',now()),
    ('2b601aaa-5463-47af-8858-f510a9d7d291','test_order.review','Review test order','Review/Duyệt patient test order.','TEST_ORDER',now()),
    ('95d8769a-eb52-4346-b175-1ecd4d235b48','comment.add','Add comment','Thêm bình luận cho test result.','COMMENT',now()),
    ('396b577b-36af-42e4-8103-46717b6611d4','comment.modify','Modify comment','Chỉnh sửa bình luận.','COMMENT',now()),
    ('b7cf08b2-86bf-4c20-9a2a-93e3f0634db1','comment.delete','Delete comment','Xoá bình luận.','COMMENT',now()),
    ('534f9f40-1f79-449f-97bc-eccd51b044d1','config.view','View configuration','Xem cấu hình, bao gồm danh mục và thiết lập.','CONFIG',now()),
    ('10fd436d-5d52-4ad0-84e0-238a1540e886','config.create','Create configuration','Tạo mới cấu hình.','CONFIG',now()),
    ('6302e164-34d8-4aa9-9a27-2ea418ca57e5','config.modify','Modify configuration','Chỉnh sửa cấu hình.','CONFIG',now()),
    ('1b75216d-fd16-4dea-a329-82131d0542d0','config.delete','Delete configuration','Xoá cấu hình.','CONFIG',now()),
    ('183c05fc-cd78-403b-8f5a-dd026a1122d3','user.view','View user','Xem hồ sơ người dùng.','USER',now()),
    ('c9604fc2-9c8a-4c0c-b973-1f48378bbcd4','user.create','Create user','Tạo người dùng mới.','USER',now()),
    ('4df6d823-e27b-4039-9c99-ef950664b418','user.modify','Modify user','Chỉnh sửa người dùng.','USER',now()),
    ('a7dc0f69-59e6-4228-b5f2-78fdbbe58707','user.delete','Delete user','Xoá người dùng.','USER',now()),
    ('7b8123ce-4091-4d5b-9733-6ae53710040a','user.lock_unlock','Lock and Unlock user','Khoá/Mở khoá người dùng.','USER',now()),
    ('7e487309-ac5c-4223-abb3-a1cf1007d4ad','role.view','View role','Xem các quyền của vai trò.','ROLE',now()),
    ('b0534608-9be9-4343-8bd7-f09b36df1d2a','role.create','Create role','Tạo vai trò tuỳ chỉnh mới.','ROLE',now()),
    ('85cd9809-2aa6-4164-ab59-b5bb84e77746','role.update','Update role','Cập nhật quyền của vai trò tuỳ chỉnh.','ROLE',now()),
    ('cd944cee-9a4b-4ef7-a952-c30d048a86ab','role.delete','Delete role','Xoá vai trò tuỳ chỉnh.','ROLE',now()),
    ('ae861974-9e7d-49da-af85-1f80c2614f2d','event_logs.view','View Event Logs','Xem nhật ký sự kiện.','SYSTEM',now()),
    ('3eca6b24-ac69-49b8-b1f2-d39413b47098','reagent.add','Add Reagents','Thêm hoá chất/vật tư.','REAGENT',now()),
    ('7d3a8dfd-68a8-435c-8653-555ac23197d3','reagent.modify','Modify Reagents','Chỉnh sửa hoá chất/vật tư.','REAGENT',now()),
    ('2ef43e9d-0eac-49c7-bd70-78bde0e9d689','reagent.delete','Delete Reagents','Xoá hoá chất/vật tư.','REAGENT',now()),
    ('b0e0973d-c22d-44b8-8d16-3c5a087dbd15','instrument.add','Add Instrument','Thêm thiết bị.','INSTRUMENT',now()),
    ('d5ed06c2-bc5a-4c54-ac79-890689344d6f','instrument.view','View Instrument','Xem danh sách/trạng thái thiết bị.','INSTRUMENT',now()),
    ('622c94fc-23ab-496a-a659-d07ed4c1d9d1','instrument.activate_deactivate','Activate/Deactivate Instrument','Kích hoạt/Vô hiệu hoá thiết bị.','INSTRUMENT',now()),
    ('dfd1216f-7c06-4e82-8839-cf4c0aac41f1','blood_test.execute','Execute Blood Testing','Thực hiện xét nghiệm huyết học.','LAB',now())
    ON CONFLICT (privilege_code) DO NOTHING;
