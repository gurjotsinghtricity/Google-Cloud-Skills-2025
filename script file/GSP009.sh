#!/bin/bash

# Define color variables
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'

# Define text formatting variables
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

clear

# Welcome message
echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...  ${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

echo "${CYAN_TEXT}${BOLD_TEXT}Creating a BigQuery dataset named 'demos'...${RESET_FORMAT}"

bq mk demos

echo "${YELLOW_TEXT}${BOLD_TEXT}Executing first BigQuery query to retrieve weather data...${RESET_FORMAT}"
bq query --use_legacy_sql=false \
"
SELECT
  -- Create a timestamp from the date components.
  stn,
  TIMESTAMP(CONCAT(year,'-',mo,'-',da)) AS timestamp,
  -- Replace numerical null values with actual null
  AVG(IF (temp=9999.9,
      null,
      temp)) AS temperature,
  AVG(IF (wdsp='999.9',
      null,
      CAST(wdsp AS Float64))) AS wind_speed,
  AVG(IF (prcp=99.99,
      0,
      prcp)) AS precipitation
FROM
  \`bigquery-public-data.noaa_gsod.gsod20*\`
WHERE
  CAST(YEAR AS INT64) > 2010
  AND CAST(MO AS INT64) = 6
  AND CAST(DA AS INT64) = 12
  AND (stn='725030' OR  -- La Guardia
    stn='744860')    -- JFK
GROUP BY
  stn,
  timestamp
ORDER BY
  timestamp DESC,
  stn ASC
"

echo "${YELLOW_TEXT}${BOLD_TEXT}Fetching New York 311 service requests data...${RESET_FORMAT}"

bq query --use_legacy_sql=false \
"
SELECT
  EXTRACT(YEAR
  FROM
    created_date) AS year,
  complaint_type,
  COUNT(1) AS num_complaints
FROM
  \`bigquery-public-data.new_york.311_service_requests\`
GROUP BY
  year,
  complaint_type
ORDER BY
  num_complaints DESC
"

echo "${MAGENTA_TEXT}${BOLD_TEXT}Storing weather data into 'demos.nyc_weather' table...${RESET_FORMAT}"

bq query --use_legacy_sql=false \
--destination_table=demos.nyc_weather \
--allow_large_results \
--replace \
--noflatten_results \
"
SELECT
  -- Create a timestamp from the date components.
  TIMESTAMP(CONCAT(year,'-',mo,'-',da)) AS timestamp,
  -- Replace numerical null values with actual nulls
  AVG(IF (temp=9999.9, NULL, temp)) AS temperature,
  AVG(IF (visib=999.9, NULL, visib)) AS visibility,
  AVG(IF (wdsp='999.9', NULL, CAST(wdsp AS FLOAT64))) AS wind_speed,
  AVG(IF (gust=999.9, NULL, gust)) AS wind_gust,
  AVG(IF (prcp=99.99, NULL, prcp)) AS precipitation,
  AVG(IF (sndp=999.9, NULL, sndp)) AS snow_depth
FROM
  \`bigquery-public-data.noaa_gsod.gsod20*\`
WHERE
  CAST(YEAR AS INT64) > 2008
  AND (stn='725030' OR stn='744860')
GROUP BY timestamp
"


echo "${CYAN_TEXT}${BOLD_TEXT}Analyzing complaints data correlation with temperature...${RESET_FORMAT}"

bq query --use_legacy_sql=false \
"
SELECT
  descriptor,
  sum(complaint_count) as total_complaint_count,
  count(temperature) as data_count,
  ROUND(corr(temperature, avg_count),3) AS corr_count,
  ROUND(corr(temperature, avg_pct_count),3) AS corr_pct
From (
SELECT
  avg(pct_count) as avg_pct_count,
  avg(day_count) as avg_count,
  sum(day_count) as complaint_count,
  descriptor,
  temperature
FROM (
  SELECT
    DATE(timestamp) AS date,
    temperature
  FROM
    demos.nyc_weather) a
  JOIN (
  SELECT x.date, descriptor, day_count, day_count / all_calls_count as pct_count
  FROM
    (SELECT
      DATE(created_date) AS date,
      concat(complaint_type, ': ', descriptor) as descriptor,
      COUNT(*) AS day_count
    FROM
      \`bigquery-public-data.new_york.311_service_requests\`
    GROUP BY
      date,
      descriptor)x
    JOIN (
      SELECT
        DATE(timestamp) AS date,
        COUNT(*) AS all_calls_count
      FROM \`demos.nyc_weather\`
      GROUP BY date
    )y
  ON x.date=y.date
)b
ON
  a.date = b.date
GROUP BY
  descriptor,
  temperature
)
GROUP BY descriptor
HAVING
  total_complaint_count > 5000 AND
  ABS(corr_pct) > 0.5 AND
  data_count > 5
ORDER BY
  ABS(corr_pct) DESC
"

echo "${MAGENTA_TEXT}${BOLD_TEXT}Analyzing complaints data correlation with wind speed...${RESET_FORMAT}"
bq query --use_legacy_sql=false \
"
SELECT
  descriptor,
  sum(complaint_count) as total_complaint_count,
  count(wind_speed) as data_count,
  ROUND(corr(wind_speed, avg_count),3) AS corr_count,
  ROUND(corr(wind_speed, avg_pct_count),3) AS corr_pct
From (
SELECT
  avg(pct_count) as avg_pct_count,
  avg(day_count) as avg_count,
  sum(day_count) as complaint_count,
  descriptor,
  wind_speed
FROM (
  SELECT
    DATE(timestamp) AS date,
    wind_speed
  FROM
    demos.nyc_weather) a
  JOIN (
  SELECT x.date, descriptor, day_count, day_count / all_calls_count as pct_count
  FROM
    (SELECT
      DATE(created_date) AS date,
      concat(complaint_type, ': ', descriptor) as descriptor,
      COUNT(*) AS day_count
    FROM
      \`bigquery-public-data.new_york.311_service_requests\`
    GROUP BY
      date,
      descriptor)x
    JOIN (
      SELECT
        DATE(timestamp) AS date,
        COUNT(*) AS all_calls_count
      FROM \`demos.nyc_weather\`
      GROUP BY date
    )y
  ON x.date=y.date
)b
ON
  a.date = b.date
GROUP BY
  descriptor,
  wind_speed
)
GROUP BY descriptor
HAVING
  total_complaint_count > 5000 AND
  ABS(corr_pct) > 0.5 AND
  data_count > 5
ORDER BY
  ABS(corr_pct) DESC

"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}              LAB COMPLETED SUCCESSFULLY!              ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
