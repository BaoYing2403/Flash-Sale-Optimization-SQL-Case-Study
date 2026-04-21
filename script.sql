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

-- QUESTION 1: Which products should be prioritized for Flash Sale?
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

-- QUESTION 2: Discount level?
-- Tạo VIEW
CREATE OR ALTER VIEW Discount_View AS
SELECT 
    Discount,
    SUM(Quantity) AS Total_Quantity,
    SUM(Profit) AS Total_Profit,
    SUM(Sales) AS Total_Revenue,
    SUM(Profit) * 1.0 / NULLIF(SUM(Sales),0) AS Profit_Margin
FROM SalesData
GROUP BY Discount;
GO

-- Query lại
SELECT *
FROM Discount_View
ORDER BY Discount;

-- QUESTION 3:
-- Question 3: Identifying Hidden Gems for Growth
WITH ProductMetrics AS (
    SELECT 
        ProductName,
        Category,
        SUM(Quantity) AS Total_Quantity,
        SUM(Profit) * 1.0 / NULLIF(SUM(Sales), 0) AS Margin,
        AVG(SUM(Quantity)) OVER() AS Avg_Quantity_System -- Lấy trung bình bán ra của cả kho
    FROM SalesData
    GROUP BY ProductName, Category
)
SELECT TOP 10
    ProductName,
    Category,
    Total_Quantity,
    CAST(Margin AS DECIMAL(18,2)) AS Profit_Margin
FROM ProductMetrics
WHERE Total_Quantity < Avg_Quantity_System -- Bán chậm hơn trung bình
  AND Margin > 0.20              -- Nhưng lợi nhuận biên vẫn rất dày (>20%)
ORDER BY Margin DESC;

-- Question 4: Category Performance by Total Volume (Promotion Impact)
WITH CategoryPerformance AS (
    SELECT 
        Category,
        -- Tổng số lượng bán ra khi KHÔNG có discount
        SUM(CASE WHEN Discount = 0 THEN Quantity ELSE 0 END) AS Total_Qty_Normal,
        -- Tổng số lượng bán ra khi CÓ discount > 0
        SUM(CASE WHEN Discount > 0 THEN Quantity ELSE 0 END) AS Total_Qty_Promo,
        -- Đếm số lượng giao dịch tương ứng để làm rõ quy mô
        COUNT(CASE WHEN Discount = 0 THEN 1 END) AS Transactions_Normal,
        COUNT(CASE WHEN Discount > 0 THEN 1 END) AS Transactions_Promo
    FROM SalesData
    GROUP BY Category
)
SELECT 
    Category,
    Total_Qty_Normal,
    Total_Qty_Promo,
    -- Tính % tăng trưởng tổng sản lượng
    CAST(((Total_Qty_Promo - Total_Qty_Normal) * 100.0 / NULLIF(Total_Qty_Normal, 0)) AS DECIMAL(10,2)) AS Volume_Growth_Percent,
    -- Hiệu suất trung bình trên mỗi giao dịch khuyến mãi (để check lại)
    CAST((Total_Qty_Promo * 1.0 / NULLIF(Transactions_Promo, 0)) AS DECIMAL(10,2)) AS Items_Per_Promo_Order
FROM CategoryPerformance
ORDER BY Volume_Growth_Percent DESC;
