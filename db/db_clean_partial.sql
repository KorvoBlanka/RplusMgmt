--
-- Partialy clean database for new user
--

DELETE FROM _query_cache;
ALTER SEQUENCE _query_cache_id_seq RESTART 1;
DELETE FROM _runtime_params;
DELETE FROM subscription_realty;
ALTER SEQUENCE subscription_realty_id_seq RESTART 1;
DELETE FROM subscriptions;
ALTER SEQUENCE subscriptions_id_seq RESTART 1;
DELETE FROM clients;
ALTER SEQUENCE clients_id_seq RESTART 1;
DELETE FROM media_import_history;
ALTER SEQUENCE media_import_history_id_seq RESTART 1;
DELETE FROM photos;
ALTER SEQUENCE photos_id_seq RESTART 1;
DELETE FROM realty;
ALTER SEQUENCE realty_id_seq RESTART 1;
DELETE FROM sms_messages;
ALTER SEQUENCE sms_messages_id_seq RESTART 1;
DELETE FROM users;
ALTER SEQUENCE users_id_seq RESTART 1;
INSERT INTO users (login, password, role, name) VALUES ('manager', 'manager', 'manager', 'Manager');
