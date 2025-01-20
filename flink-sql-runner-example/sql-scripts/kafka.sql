CREATE TABLE kafka_topic_input (
    `timestamp` STRING,         
    `page` STRING,
    `event_time` AS PROCTIME()    
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
    `windowStart` TIMESTAMP(3),  
    `windowEnd` TIMESTAMP(3),    
    `page` STRING,         
    `cc` BIGINT       
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
    window_start AS `windowStart`,
    window_end AS `windowEnd`,
    `page`,
    COUNT(`timestamp`) AS `cc`
FROM TABLE(
   TUMBLE(TABLE kafka_topic_input, DESCRIPTOR(`event_time`), INTERVAL '15' SECONDS))
GROUP BY window_start, window_end, `page`;
