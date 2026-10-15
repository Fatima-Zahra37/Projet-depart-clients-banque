-- =====================================================================
-- Vérification des chiffres clés — Départs clients cartes de crédit
-- Outil : DuckDB — à exécuter depuis la racine du projet
-- Résultats attendus : identiques au notebook 02 (Python)
-- =====================================================================

-- 1. Chargement : table clients avec indicateur de départ (1 = parti, 0 = actif)
CREATE OR REPLACE TABLE clients AS
SELECT *,
       CASE WHEN Attrition_Flag = 'Attrited Customer' THEN 1 ELSE 0 END AS parti
FROM read_csv_auto('data/BankChurners.csv');

-- 2. Indicateurs globaux
--    Attendu : 10 127 clients, 1 627 partis, 16,1 % de départs
SELECT COUNT(*)                   AS nb_clients,
       SUM(parti)::INT            AS nb_partis,
       ROUND(AVG(parti) * 100, 1) AS taux_depart_pct
FROM clients;

-- 3. Grille des 6 signaux d'alerte : nombre de signaux par client
CREATE OR REPLACE VIEW signaux AS
WITH seuils AS (
    SELECT QUANTILE_CONT(Total_Trans_Ct, 0.25)      AS seuil_transactions,
           QUANTILE_CONT(Total_Ct_Chng_Q4_Q1, 0.25) AS seuil_evolution
    FROM clients
)
SELECT c.CLIENTNUM,
       c.parti,
         (c.Total_Trans_Ct <= s.seuil_transactions)::INT   -- activité faible
       + (c.Total_Ct_Chng_Q4_Q1 <= s.seuil_evolution)::INT -- forte baisse d'activité
       + (c.Total_Revolving_Bal = 0)::INT                  -- sans encours
       + (c.Total_Relationship_Count <= 2)::INT            -- 1 ou 2 produits
       + (c.Months_Inactive_12_mon >= 3)::INT              -- 3 mois d'inactivité ou plus
       + (c.Contacts_Count_12_mon >= 4)::INT               -- 4 contacts ou plus
       AS nb_signaux
FROM clients AS c
CROSS JOIN seuils AS s;

-- 4. Taux de départ selon le nombre de signaux
SELECT nb_signaux,
       COUNT(*)             AS nb_clients,
       ROUND(AVG(parti), 3) AS taux_depart
FROM signaux
GROUP BY nb_signaux
ORDER BY nb_signaux;

-- 5. Cible prioritaire : clients cumulant au moins 3 signaux
--    Attendu : 1 900 clients, 54,8 % de départs, 64,0 % des départs couverts
SELECT COUNT(*) FILTER (WHERE nb_signaux >= 3)                                  AS clients_cibles,
       ROUND(AVG(parti) FILTER (WHERE nb_signaux >= 3) * 100, 1)                AS taux_depart_cible_pct,
       ROUND(SUM(parti) FILTER (WHERE nb_signaux >= 3) * 100.0 / SUM(parti), 1) AS part_departs_couverts_pct
FROM signaux;