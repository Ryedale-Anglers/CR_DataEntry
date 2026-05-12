CREATE OR REPLACE VIEW public.view_members_reserv_and_cr_history as
SELECT 
    vrcs.date,
    vrcs.cr_name,
    vrcs.beat,
    crst.brown_trout_released + crst.brown_trout_retained AS brown_trout,
    crst.grayling,
    crst.comments
FROM view_reservations_confirmed_staging vrcs
LEFT JOIN ( 
    SELECT 
        catch_returns_staging_table.rod_name,
        catch_returns_staging_table.catch_date,
        catch_returns_staging_table.brown_trout_released,
        catch_returns_staging_table.brown_trout_retained,
        catch_returns_staging_table.grayling,
        catch_returns_staging_table.comments,
        -- We rank to get the latest return, specifically for NON-GUESTS who DID FISH
        row_number() OVER (
            PARTITION BY catch_returns_staging_table.catch_date, catch_returns_staging_table.rod_name 
            ORDER BY catch_returns_staging_table."timestamp" DESC
        ) AS rn
    FROM catch_returns_staging_table
    WHERE catch_returns_staging_table.dnf = false 
      AND catch_returns_staging_table.guest = false -- Keeps guest data out of the counts
) crst 
    ON vrcs.date = crst.catch_date 
    AND vrcs.cr_name = crst.rod_name 
    AND crst.rn = 1
WHERE NOT EXISTS ( 
    -- ONLY disqualify the reservation if they explicitly said they Didn't Fish
    SELECT 1
    FROM catch_returns_staging_table disqualified
    WHERE disqualified.catch_date = vrcs.date 
      AND disqualified.rod_name = vrcs.cr_name 
      AND disqualified.dnf = true
)
ORDER BY vrcs.date, vrcs.cr_name;