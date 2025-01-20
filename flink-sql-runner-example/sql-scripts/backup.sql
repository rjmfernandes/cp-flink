

CREATE TABLE debug_sink (
    `window_start` TIMESTAMP(3),
    `window_end` TIMESTAMP(3),
    `page` STRING,
    `cc` BIGINT
) WITH (
    'connector' = 'print'
);

INSERT INTO debug_sink
SELECT 
    TUMBLE_START(`event_time`, INTERVAL '15' SECOND) AS window_start,
    TUMBLE_END(`event_time`, INTERVAL '15' SECOND) AS window_end,
    `page`,
    COUNT(*) AS cc
FROM kafka_topic_input
GROUP BY 
    TUMBLE(`event_time`, INTERVAL '15' SECOND),
    `page`;



CREATE TABLE kafka_topic_input (
    `timestamp` STRING,
    `page` STRING,
    `event_time` AS TO_TIMESTAMP(`timestamp`, 'dd-MM-yyyy HH:mm:ss:SSS'),
     WATERMARK FOR `event_time` AS `event_time` - INTERVAL '1' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'input',
    'properties.bootstrap.servers' = 'kafka.confluent.svc.cluster.local:9092',
    'properties.group.id' = 'flink-sql-consumer-group',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.fail-on-missing-field' = 'true',
    'json.ignore-parse-errors' = 'false'
);

CREATE TABLE kafka_topic_output (
    `windowStart` STRING,  
    `windowEnd` STRING,    
    `page` STRING,         
    `cc` BIGINT,
    `window_time` AS TO_TIMESTAMP(`windowEnd`, 'dd-MM-yyyy HH:mm:ss:SSS'),  
    WATERMARK FOR `window_time` AS `window_time` - INTERVAL '1' SECOND            
) WITH (
    'connector' = 'kafka',
    'topic' = 'output2',                                      
    'properties.bootstrap.servers' = 'kafka.confluent.svc.cluster.local:9092',  
    'format' = 'json',                                      
    'json.fail-on-missing-field' = 'true',                 
    'json.ignore-parse-errors' = 'false'                     
);

INSERT INTO kafka_topic_output
SELECT 
    DATE_FORMAT(window_start, 'dd-MM-yyyy HH:mm:ss:SSS') AS windowStart,
    DATE_FORMAT(window_end, 'dd-MM-yyyy HH:mm:ss:SSS') AS windowEnd,
    `page`,
    COUNT(*) AS `cc`
FROM TABLE(
   TUMBLE(TABLE kafka_topic_input, DESCRIPTOR(`event_time`), INTERVAL '15' SECONDS))
GROUP BY window_start, window_end, `page`;
