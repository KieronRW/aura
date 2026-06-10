# Supabase Schema Reference

## visitors
| Column | Type |
|---|---|
| id | uuid |
| installation_id | uuid |
| name | text |
| vehicle_make | text |
| vehicle_model | text |
| registration | text |
| greeting | text |
| notes | text |
| expected_from | timestamptz |
| expected_until | timestamptz |
| is_active | boolean |
| created_at | timestamptz |
| updated_at | timestamptz |

## unknown_vehicles
| Column | Type |
|---|---|
| id | uuid |
| installation_id | uuid |
| image_path | text |
| confidence | float |
| quality_score | float |
| detected_make | text |
| detected_model | text |
| metadata | jsonb |
| status | enum: unreviewed / assigned / dismissed |
| assigned_vehicle_id | uuid |
| assigned_at | timestamptz |
| assigned_by | uuid |
| created_at | timestamptz |

## recognition_events
| Column | Type |
|---|---|
| id | uuid |
| installation_id | uuid |
| profile_id | uuid |
| vehicle_id | uuid |
| visitor_id | uuid |
| detected_make | text |
| detected_model | text |
| confidence | float |
| method | text |
| image_path | text |
| metadata | jsonb |
| arrived_at | timestamptz |
| departed_at | timestamptz |
| created_at | timestamptz |
| confidence_tier | text |
| quality_passed | boolean |
| quality_score | float |
| needs_review | boolean |
| reviewed | boolean |
| review_notes | text |

## vehicles
| Column | Type |
|---|---|
| id | uuid |
| profile_id | uuid |
| make | text |
| model | text |
| colour | text |
| registration | text |
| nickname | text |
| year | integer |
| owner_name | text |
| owner_greeting | text |
| fingerprint_data | jsonb |
| fingerprint_seeded | boolean |
| reference_image_count | integer |
| confidence_threshold | float |
| confidence_high | float |
| confidence_medium | float |
| vision_confirmed | boolean |
| vision_confirmation_count | integer |
| custom_badge_path | text |
| is_active | boolean |
| fingerprint_score | float |
| created_at | timestamptz |
| updated_at | timestamptz |

## vehicle_reference_images
| Column | Type |
|---|---|
| id | uuid |
| vehicle_id | uuid |
| storage_path | text |
| angle | enum: front / rear / side / three_quarter / auto |
| file_size_bytes | bigint |
| fingerprint_data | jsonb |
| is_active | boolean |
| created_at | timestamptz |

## profiles
| Column | Type |
|---|---|
| id | uuid |
| installation_id | uuid |
| first_name | text |
| last_name | text |
| display_name | text |
| greeting | text |
| avatar_path | text |
| face_enrolled | boolean |
| is_active | boolean |
| created_at | timestamptz |
| updated_at | timestamptz |

## installations
| Column | Type |
|---|---|
| id | uuid |
| property_id | uuid |
| name | text |
| serial_number | text |
| hardware_version | text |
| software_version | text |
| display_orientation | enum |
| timezone | text |
| location_description | text |
| installation_key | text |
| is_active | boolean |
| status | text |
| claimed_at | timestamptz |
| claimed_by | uuid |
| last_reset_at | timestamptz |
| reset_count | integer |
| created_at | timestamptz |
| updated_at | timestamptz |

## properties
| Column | Type |
|---|---|
| id | uuid |
| user_id | uuid |
| name | text |
| address | text |
| timezone | text |
| is_active | boolean |
| created_at | timestamptz |
| updated_at | timestamptz |

## device_status
| Column | Type |
|---|---|
| installation_id | uuid |
| is_online | boolean |
| last_seen_at | timestamptz |
| local_ip | text |
| uptime_seconds | bigint |
| cpu_percent | float |
| memory_percent | float |
| disk_percent | float |
| software_version | text |
| camera_ok | boolean |
| display_clients | integer |
| current_state | text |
| updated_at | timestamptz |
