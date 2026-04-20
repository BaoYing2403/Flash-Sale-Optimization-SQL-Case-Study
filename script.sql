-- Chọn Database để làm việc
USE FlashSalePj; 
GO

-- Xóa bảng cũ nếu có để làm mới hoàn toàn
IF OBJECT_ID('SalesData', 'U') IS NOT NULL DROP TABLE SalesData;

-- Tạo bảng 
CREATE TABLE SalesData (
    OrderID NVARCHAR(50) PRIMARY KEY,
    OrderDate DATE,
    Customer NVARCHAR(255),
    Region NVARCHAR(100),
    City NVARCHAR(100),
    Category NVARCHAR(100),
    SubCategory NVARCHAR(100),
    ProductName NVARCHAR(MAX),
    Quantity INT,
    UnitPrice DECIMAL(18, 2),
    Discount DECIMAL(5, 2),
    Sales DECIMAL(18, 2),
    Profit DECIMAL(18, 2),
    PaymentMode NVARCHAR(100)
);
GO

-- Nạp dữ liệu (Đã lược bỏ ENCODING để tránh lỗi cú pháp)
BULK INSERT SalesData
FROM 'C:\Users\Public\Ecommerce_Sales_Data_2024_2025.csv' -- Hãy đảm bảo tên file trong ổ C là sales.csv
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',', 
    ROWTERMINATOR = '\n'   -- Nếu vẫn lỗi dòng này, hãy thử thay bằng '0x0a'
);
GO

-- Question 1: Which products should be prioritized for Flash Sale?
WITH ProductPerformance AS (
    SELECT 
        ProductName,
        Category,

        -- Core metrics
        SUM(Quantity) AS Total_Quantity,
        SUM(Sales) AS Total_Revenue,
        SUM(Profit) AS Total_Profit,
        COUNT(DISTINCT OrderID) AS Order_Frequency,
        AVG(Discount) AS Avg_Discount

    FROM SalesData
    WHERE Sales > 0
    GROUP BY ProductName, Category
),
Ranking AS (
    SELECT *,
    
        -- Ranking từng yếu tố
        RANK() OVER (ORDER BY Total_Revenue DESC) AS Revenue_Rank,
        RANK() OVER (ORDER BY Total_Quantity DESC) AS Quantity_Rank,
        RANK() OVER (ORDER BY Order_Frequency DESC) AS Frequency_Rank

    FROM ProductPerformance
),
Scoring AS (
    SELECT *,

        -- Weighted score (ưu tiên revenue)
        (0.5 * Revenue_Rank 
        + 0.3 * Quantity_Rank 
        + 0.2 * Frequency_Rank) AS Combined_Score

    FROM Ranking
),
Segmentation AS (
    SELECT *,
        CASE 
            WHEN Revenue_Rank <= 10 AND Quantity_Rank <= 10 THEN 'Star Product'
            WHEN Revenue_Rank <= 10 THEN 'High Value Product'
            WHEN Quantity_Rank <= 10 OR Frequency_Rank <= 10 THEN 'High Demand Product'
            ELSE 'Others'
        END AS Product_Type
    FROM Scoring
)

SELECT 
    ProductName,
    Category,
    Total_Revenue,
    Total_Quantity,
    Order_Frequency,
    Total_Profit,
    Product_Type,
    Combined_Score
FROM Segmentation
-- chọn sản phẩm phù hợp Flash Sale
WHERE Product_Type IN ('Star Product', 'High Demand Product')
ORDER BY Combined_Score ASC;
