CREATE TABLE click_to_landing_analysis (
    Record_ID VARCHAR(20) PRIMARY KEY,
    Date DATE NOT NULL,
    Channel VARCHAR(50) NOT NULL,
    Campaign VARCHAR(100) NOT NULL,
    Device VARCHAR(20) NOT NULL,
    Browser VARCHAR(30) NOT NULL,
    Ad_Impressions INTEGER NOT NULL,
    Ad_Clicks INTEGER NOT NULL,
	Ad_CTR_pct NUMERIC(5,2),
	Cost_per_Click_USD NUMERIC(5,2),
    Ad_Spend_USD NUMERIC(12,2) NOT NULL,
    Recorded_Landing_Visits INTEGER NOT NULL,
	Click_to_Landing_Rate_pct NUMERIC(5,2),
    Click_Loss_Rate_pct NUMERIC(5,2),
    FCP_seconds NUMERIC(6,2),
    TTI_seconds NUMERIC(6,2),
    Avg_Page_Load_Time_seconds NUMERIC(6,2),
    Page_Availability_pct NUMERIC(5,2),
    Page_Error_Count INTEGER,
    Redirect_Count_Avg INTEGER,
    Redirect_Error_Rate_pct NUMERIC(5,2),
    Redirect_Type VARCHAR(30),
    Server_Requests INTEGER,
    Analytics_Sessions INTEGER,
    Analytics_Tracking_Status VARCHAR(20),
    UTM_Parameters_Status VARCHAR(30),
    Server_vs_Analytics_Gap_pct NUMERIC(6,2),
    Bounce_0_2_Sec_Count INTEGER,
    Accidental_or_Invalid_Click_Rate_pct NUMERIC(5,2),
    Landing_Page_Status VARCHAR(30),
    Notes TEXT
);

select * from click_to_landing_analysis

-- 1. How big is the problem, and what does it cost?

SELECT
    SUM(Ad_Clicks) AS total_clicks,
    SUM(Recorded_Landing_Visits) AS total_visits,
   ROUND(SUM(Recorded_Landing_Visits) * 100.0 / NULLIF(SUM(Ad_Clicks), 0), 2) AS Click_to_Landing_Rate_pct,
   ROUND(100.0 - (SUM(Recorded_Landing_Visits) * 100.0 / NULLIF(SUM(Ad_Clicks), 0)), 2) AS Click_Loss_Rate_pct,
   ROUND(SUM((Ad_Clicks-Recorded_Landing_Visits)*Cost_per_Click_USD),2) AS wasted_usd,
   SUM(Ad_Spend_USD) AS total_spend
FROM click_to_landing_analysis;

-- 2. Where is the loss? (channel / campaign / device+browser)

SELECT Channel, Campaign,
  SUM(Ad_Clicks) AS clicks,
  ROUND(100.0 - 100.0 * SUM(Recorded_Landing_Visits) / NULLIF(SUM(Ad_Clicks),0), 2) AS loss_pct,
  ROUND(SUM((Ad_Clicks - Recorded_Landing_Visits) * Cost_per_Click_USD), 2) AS wasted_usd,
  ROUND(100.0 * SUM((Ad_Clicks - Recorded_Landing_Visits) * Cost_per_Click_USD)
        / SUM(SUM((Ad_Clicks - Recorded_Landing_Visits) * Cost_per_Click_USD)) OVER (), 1) AS pct_of_waste
FROM click_to_landing_analysis
GROUP BY Channel, Campaign
ORDER BY wasted_usd DESC;

SELECT Device, Browser,
  SUM(Ad_Clicks) AS clicks,
  ROUND(100.0 - 100.0 * SUM(Recorded_Landing_Visits) / NULLIF(SUM(Ad_Clicks),0), 2) AS loss_pct,
  ROUND(SUM((Ad_Clicks - Recorded_Landing_Visits) * Cost_per_Click_USD), 2) AS wasted_usd,
  ROUND(100.0 * SUM((Ad_Clicks - Recorded_Landing_Visits) * Cost_per_Click_USD)
        / SUM(SUM((Ad_Clicks - Recorded_Landing_Visits) * Cost_per_Click_USD)) OVER (), 1) AS pct_of_waste
FROM click_to_landing_analysis
GROUP BY Device, Browser
ORDER BY wasted_usd DESC;

-- 3. Is it the page? (speed, errors, redirects)

SELECT
  Device,
  Browser,
  ROUND(AVG(Page_Availability_pct), 1) AS availability,
  ROUND(AVG(Avg_Page_Load_Time_seconds),1) As page_load_time,
  ROUND(AVG(FCP_seconds), 1) AS fcp,
  ROUND(AVG(TTI_seconds), 1) AS tti,
  ROUND(AVG(Page_Error_Count), 1) AS errors,
  ROUND(AVG(Redirect_Count_Avg), 1) AS redirect_hops,
  ROUND(AVG(Redirect_Error_Rate_pct), 1) AS redirect_errors,
  ROUND(100.0 - 100.0 * SUM(Recorded_Landing_Visits) / SUM(Ad_Clicks), 2) AS loss_pct 
FROM click_to_landing_analysis
GROUP BY Device, Browser
ORDER BY availability;

-- 4. Verify the correlation (don't assume it)

SELECT Landing_Page_Status, COUNT(*) AS rows_n,
  ROUND(AVG(Click_Loss_Rate_pct),2) AS avg_loss_pct
FROM click_to_landing_analysis GROUP BY Landing_Page_Status;

SELECT COALESCE(Redirect_Type,'None') AS redirect_type, Redirect_Count_Avg,
  COUNT(*) AS rows_n, ROUND(AVG(Click_Loss_Rate_pct),2) AS avg_loss_pct
FROM click_to_landing_analysis
GROUP BY 1,2 ORDER BY avg_loss_pct DESC;

-- 5. Is it the tracking? (the funnel)
SELECT
  Device,
  Browser,
  SUM(Ad_Clicks) AS clicks,
  SUM(Server_Requests) AS server,
  SUM(Analytics_Sessions) AS analytics,
  SUM(Ad_Clicks) - SUM(Server_Requests) AS never_reached_site,
  SUM(Server_Requests) - SUM(Analytics_Sessions) AS reached_but_not_counted
FROM click_to_landing_analysis
GROUP BY Device, Browser
ORDER BY never_reached_site DESC;

-- 6. is the tracking broken?
SELECT Device, Browser, Analytics_Tracking_Status, UTM_Parameters_Status,
  COUNT(*) AS rows_n,
  ROUND(AVG(Server_vs_Analytics_Gap_pct),2) AS avg_gap
FROM click_to_landing_analysis
GROUP BY 1,2,3,4 ORDER BY avg_gap DESC;

-- 7. Are the clicks fake?
SELECT Device, Browser,
round(avg(Accidental_or_Invalid_Click_Rate_pct),2) as invalid_click_pct,
round(100.0*sum(Bounce_0_2_Sec_Count)/sum(Recorded_Landing_Visits),1) AS fast_bounce_pct
FROM click_to_landing_analysis
GROUP BY 1,2 ORDER BY invalid_click_pct DESC;

-- 8. If we fix Mobile Safari to match the healthy 5% baseline, 
-- how much wasted spend do we get back?
SELECT 
    -- Current wasted spend on Mobile Safari
    SUM((Ad_Clicks - Recorded_Landing_Visits) * Cost_per_Click_USD) AS current_waste,
    
    -- What the waste WOULD be if Mobile Safari had a healthy 5% loss rate
    SUM(Ad_Clicks * 0.05 * Cost_per_Click_USD) AS healthy_baseline_waste,
    
    -- The difference is the money you save
    SUM((Ad_Clicks - Recorded_Landing_Visits) * Cost_per_Click_USD) - SUM(Ad_Clicks * 0.05 * Cost_per_Click_USD) AS recoverable_money
FROM click_to_landing_analysis
WHERE Device = 'Mobile' AND Browser = 'Safari';







