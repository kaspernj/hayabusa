class Hayabusa::Database
  SCHEMA = {
    "tables" => {
      "Log" => {
        "columns" => [
          {"name" => "id", "type" => "bigint", "autoincr" => true, "primarykey" => true},
          {"name" => "text_value_id", "type" => "bigint"},
          {"name" => "date_saved", "type" => "datetime"},
          {"name" => "get_keys_data_id", "type" => "bigint"},
          {"name" => "get_values_data_id", "type" => "bigint"},
          {"name" => "post_keys_data_id", "type" => "bigint"},
          {"name" => "post_values_data_id", "type" => "bigint"},
          {"name" => "cookie_keys_data_id", "type" => "bigint"},
          {"name" => "cookie_values_data_id", "type" => "bigint"},
          {"name" => "meta_keys_data_id", "type" => "bigint"},
          {"name" => "meta_values_data_id", "type" => "bigint"},
          {"name" => "session_keys_data_id", "type" => "bigint"},
          {"name" => "session_values_data_id", "type" => "bigint"},
          {"name" => "tag_data_id", "type" => "bigint"},
          {"name" => "comment_data_id", "type" => "bigint"}
        ],
        "indexes" => [
          {"name" => "text_value_id", "columns" => ["text_value_id"]},
          {"name" => "tag_data_id", "columns" => ["tag_data_id"]},
          {"name" => "comment_data_id", "columns" => ["comment_data_id"]}
        ]
      },
      "Log_access" => {
        "columns" => [
          {"name" => "id", "type" => "bigint", "autoincr" => true, "primarykey" => true},
          {"name" => "session_id", "type" => "bigint"},
          {"name" => "date_request", "type" => "datetime"},
          {"name" => "ip_data_id", "type" => "bigint"},
          {"name" => "get_keys_data_id", "type" => "bigint"},
          {"name" => "get_values_data_id", "type" => "bigint"},
          {"name" => "post_keys_data_id", "type" => "bigint"},
          {"name" => "post_values_data_id", "type" => "bigint"},
          {"name" => "cookie_keys_data_id", "type" => "bigint"},
          {"name" => "cookie_values_data_id", "type" => "bigint"},
          {"name" => "meta_keys_data_id", "type" => "bigint"},
          {"name" => "meta_values_data_id", "type" => "bigint"}
        ],
        "indexes" =>  [
          {"name" => "session_id", "columns" => ["session_id"]},
          {"name" => "date_request", "columns" => ["date_request"]}
        ]
      },
      "Log_data" => {
        "columns" => [
          {"name" => "id", "type" => "bigint", "autoincr" => true, "primarykey" => true},
          {"name" => "id_hash", "type" => "varchar"}
        ],
        "indexes" => [
          {"name" => "id_hash", "columns" => ["id_hash"]}
        ]
      },
      "Log_data_link" => {
        "columns" => [
          {"name" => "id", "type" => "bigint", "autoincr" => true, "primarykey" => true},
          {"name" => "no", "type" => "int"},
          {"name" => "data_id", "type" => "bigint"},
          {"name" => "value_id", "type" => "bigint"}
        ],
        "indexes" => [
          {"name" => "data_id", "columns" => ["data_id"]},
          {"name" => "value_id", "columns" => ["value_id"]}
        ]
      },
      "Log_data_value" => {
        "columns" => [
          {"name" => "id", "type" => "bigint", "autoincr" => true, "primarykey" => true},
          {"name" => "value", "type" => "text"}
        ]
      },
      "Log_link" => {
        "columns" => [
          {"name" => "id", "type" => "bigint", "autoincr" => true, "primarykey" => true},
          {"name" => "log_id", "type" => "bigint"},
          {"name" => "object_class_value_id", "type" => "bigint"},
          {"name" => "object_id", "type" => "bigint"}
        ],
        "indexes" => [
          {"name" => "log_id", "columns" => ["log_id"]},
          {"name" => "object_id", "columns" => ["object_id"]},
          {"name" => "object_class_value_id", "columns" => ["object_class_value_id"]},
          {"name" => "object_lookup", "columns" => ["object_class_value_id", "object_id"]},
          {"name" => "log_lookup", "columns" => ["object_class_value_id", "object_id", "log_id"]}
        ]
      },
      "Session" => {
        "columns" => [
          {"name" => "id", "type" => "bigint", "autoincr" => true, "primarykey" => true},
          {"name" => "idhash", "type" => "varchar"},
          {"name" => "sess_data", "type" => "text"},
          {"name" => "date_added", "type" => "datetime"},
          {"name" => "date_lastused", "type" => "datetime", "on_created" => proc{|d| d["db"].query("UPDATE Session SET date_lastused = '#{Datet.new.dbstr}'")}},
          {"name" => "ip", "type" => "varchar", "maxlength" => 15},
          {"name" => "user_agent", "type" => "text"},
          {"name" => "remember", "type" => "enum", "maxlength" => "'0','1'", "default" => 0, "comment" => "If the session should be remembered or not."}
        ],
        "indexes" => [
          {"name" => "date_added", "columns" => ["date_added"]},
          {"name" => "idhash", "columns" => ["idhash"]}
        ]
      },
      "Translation" => {
        "columns" => [
          {"name" => "id", "type" => "bigint", "autoincr" => true, "primarykey" => true},
          {"name" => "object_class", "type" => "varchar", "maxlength" => 50},
          {"name" => "object_id", "type" => "bigint"},
          {"name" => "key", "type" => "varchar", "maxlength" => 50},
          {"name" => "locale", "type" => "varchar", "maxlength" => 5},
          {"name" => "value", "type" => "text"}
        ],
        "indexes" => [
          {"name" => "lookup", "columns" => ["object_class", "object_id", "key", "locale"]}
        ]
      }
    }
  }
end