-- Rules are data; this stops malformed rules from being stored.
ALTER TABLE "rule"
    ADD CONSTRAINT rule_json_valid
    CHECK (
        (condition IS NULL OR jsonb_typeof(condition::jsonb) = 'object')
        AND jsonb_typeof(effect_template::jsonb) = 'object'
        AND (effect_template::jsonb) ? 'action'
    );
