SET search_path = iamservice_db, public;
INSERT INTO role_privileges (role_id, privilege_id)
SELECT r.role_id, p.privilege_id
FROM roles r
         CROSS JOIN privileges p
WHERE r.role_code = 'ADMIN'
    ON CONFLICT DO NOTHING;
INSERT INTO role_privileges (role_id, privilege_id)
SELECT r.role_id, p.privilege_id
FROM roles r
         JOIN privileges p ON p.privilege_code IN (
                                                   'test_order.create',
                                                   'test_order.modify',
                                                   'test_order.delete',
                                                   'test_order.review',
                                                   'reagent.add',
                                                   'reagent.modify',
                                                   'reagent.delete',
                                                   'instrument.view',
                                                   'instrument.activate_deactivate',
                                                   'blood_test.execute',
                                                   'comment.add',
                                                   'comment.modify',
                                                   'comment.delete',
                                                   'event_logs.view'
    )
WHERE r.role_code = 'LAB_MANAGER'
    ON CONFLICT DO NOTHING;
INSERT INTO role_privileges (role_id, privilege_id)
SELECT r.role_id, p.privilege_id
FROM roles r
         JOIN privileges p ON p.privilege_code IN (
                                                   'test_order.review',
                                                   'test_order.modify',
                                                   'instrument.add',
                                                   'instrument.view',
                                                   'blood_test.execute',
                                                   'comment.add',
                                                   'comment.modify'
    )
WHERE r.role_code = 'LAB_TECH'
    ON CONFLICT DO NOTHING;
INSERT INTO role_privileges (role_id, privilege_id)
SELECT r.role_id, p.privilege_id
FROM roles r
         JOIN privileges p ON p.privilege_code IN (
                                                   'test_order.review',
                                                   'comment.add'
    )
WHERE r.role_code = 'LAB_USER'
    ON CONFLICT DO NOTHING;
INSERT INTO role_privileges (role_id, privilege_id)
SELECT r.role_id, p.privilege_id
FROM roles r
         JOIN privileges p ON p.privilege_code IN (
                                                   'config.view',
                                                   'config.create',
                                                   'config.modify',
                                                   'config.delete',
                                                   'event_logs.view',
                                                   'role.view'
    )
WHERE r.role_code = 'SERVICE'
    ON CONFLICT DO NOTHING;
INSERT INTO role_privileges (role_id, privilege_id)
SELECT r.role_id, p.privilege_id
FROM roles r
         JOIN privileges p ON p.privilege_code IN (
    'system.read_only'
    )
WHERE r.role_code = 'USER'
    ON CONFLICT DO NOTHING;
