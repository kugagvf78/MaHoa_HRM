/* =========================================================
   SCRIPT SQL - MÔ HÌNH DBMS MÙ DỮ LIỆU THẬT

   SQL Server chỉ lưu:
   - Dữ liệu mã hóa: I_Holot, I_Ten, I_CMND, I_Sotaikhoan
   - Hash tra cứu: CMNDHash, SotaikhoanHash
   - SecureIndex: GramHash

   SQL Server không giữ khóa, không mã hóa, không giải mã.
   Toàn bộ AES encrypt/decrypt, SHA-256 hash và Phase 2 verify
   được xử lý ở Middleware C#.
   ========================================================= */

-- 1. THÊM CỘT HASH VÀ CỘT DỮ LIỆU MÃ HÓA

IF COL_LENGTH('dbo.Tbl_Nhanvien', 'CMNDHash') IS NULL
    ALTER TABLE dbo.Tbl_Nhanvien ADD CMNDHash VARBINARY(32) NULL;
GO

IF COL_LENGTH('dbo.Tbl_Nhanvien', 'SotaikhoanHash') IS NULL
    ALTER TABLE dbo.Tbl_Nhanvien ADD SotaikhoanHash VARBINARY(32) NULL;
GO

IF COL_LENGTH('dbo.Tbl_Nhanvien', 'I_Holot') IS NULL
    ALTER TABLE dbo.Tbl_Nhanvien ADD I_Holot VARBINARY(MAX) NULL;
GO

IF COL_LENGTH('dbo.Tbl_Nhanvien', 'I_Ten') IS NULL
    ALTER TABLE dbo.Tbl_Nhanvien ADD I_Ten VARBINARY(MAX) NULL;
GO

IF COL_LENGTH('dbo.Tbl_Nhanvien', 'I_CMND') IS NULL
    ALTER TABLE dbo.Tbl_Nhanvien ADD I_CMND VARBINARY(512) NULL;
GO

IF COL_LENGTH('dbo.Tbl_Nhanvien', 'I_Sotaikhoan') IS NULL
    ALTER TABLE dbo.Tbl_Nhanvien ADD I_Sotaikhoan VARBINARY(512) NULL;
GO


-- 2. TẠO BẢNG SECUREINDEX

IF OBJECT_ID('dbo.SecureIndex', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SecureIndex
    (
        Id BIGINT IDENTITY(1,1) PRIMARY KEY,
        RecordId INT NOT NULL,
        TableName NVARCHAR(100) NOT NULL,
        ColumnName NVARCHAR(100) NOT NULL,
        GramHash VARBINARY(32) NOT NULL,
        Position INT NULL,
        DateCreated DATETIME NOT NULL DEFAULT GETDATE()
    );
END
GO


--  2.1. XÓA CỘT GRAMVALUE NẾU ĐÃ TỪNG TẠO Ở PHIÊN BẢN CŨ

IF COL_LENGTH('dbo.SecureIndex', 'GramValue') IS NOT NULL
BEGIN
    ALTER TABLE dbo.SecureIndex DROP COLUMN GramValue;
END
GO


-- 2.2. TẠO INDEX CHO BẢNG SECUREINDEX
IF NOT EXISTS (
    SELECT 1 
    FROM sys.indexes 
    WHERE name = 'IX_SecureIndex_Table_Column_GramHash' 
      AND object_id = OBJECT_ID('dbo.SecureIndex')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_SecureIndex_Table_Column_GramHash
    ON dbo.SecureIndex(TableName, ColumnName, GramHash)
    INCLUDE (RecordId, Position);
END
GO

IF NOT EXISTS (
    SELECT 1 
    FROM sys.indexes 
    WHERE name = 'IX_SecureIndex_RecordId' 
      AND object_id = OBJECT_ID('dbo.SecureIndex')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_SecureIndex_RecordId
    ON dbo.SecureIndex(RecordId, TableName, ColumnName);
END
GO


-- 2.3. TẠO INDEX CHO TRA CỨU CHÍNH XÁC BẰNG HASH
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_Tbl_Nhanvien_CMNDHash'
      AND object_id = OBJECT_ID('dbo.Tbl_Nhanvien')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Tbl_Nhanvien_CMNDHash
    ON dbo.Tbl_Nhanvien(CMNDHash)
    INCLUDE (Id_NV, Disable);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_Tbl_Nhanvien_SotaikhoanHash'
      AND object_id = OBJECT_ID('dbo.Tbl_Nhanvien')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Tbl_Nhanvien_SotaikhoanHash
    ON dbo.Tbl_Nhanvien(SotaikhoanHash)
    INCLUDE (Id_NV, Disable);
END
GO


-- 3. TẠO TABLE TYPE CHỨA DANH SÁCH HASH
IF TYPE_ID(N'dbo.VarbinaryHashList') IS NULL
BEGIN
    CREATE TYPE dbo.VarbinaryHashList AS TABLE
    (
        HashValue VARBINARY(32) NOT NULL
    );
END
GO


-- 4. STORED PROCEDURE THÊM NHÂN VIÊN
CREATE OR ALTER PROCEDURE dbo.sp_Tbl_Nhanvien_Insert
    @MaNV NVARCHAR(50),
    @I_Holot VARBINARY(MAX) = NULL,
    @I_Ten VARBINARY(MAX) = NULL,
    @I_CMND VARBINARY(512) = NULL,
    @CMNDHash VARBINARY(32) = NULL,
    @Ngaysinh DATETIME = NULL,
    @Mobile VARCHAR(20) = NULL,
    @Email NVARCHAR(255) = NULL,
    @I_Sotaikhoan VARBINARY(512) = NULL,
    @SotaikhoanHash VARBINARY(32) = NULL,
    @CreatedUser NUMERIC(18,0) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NewIds TABLE (Id_NV NUMERIC(18,0));

    INSERT INTO dbo.Tbl_Nhanvien
    (
        MaNV,
        Holot,
        Ten,
        I_Holot,
        I_Ten,
        CMND,
        I_CMND,
        CMNDHash,
        I_Sotaikhoan,
        SotaikhoanHash,
        Ngaysinh,
        Mobile,
        Email,
        DateCreated,
        CreatedUser,
        LastModified,
        LastModifiedUser,
        Disable
    )
    OUTPUT INSERTED.Id_NV INTO @NewIds(Id_NV)
    VALUES
    (
        NULLIF(@MaNV, ''),
        NULL,
        NULL,
        @I_Holot,
        @I_Ten,
        NULL,
        @I_CMND,
        @CMNDHash,
        @I_Sotaikhoan,
        @SotaikhoanHash,
        @Ngaysinh,
        NULLIF(@Mobile, ''),
        NULLIF(@Email, ''),
        GETDATE(),
        @CreatedUser,
        GETDATE(),
        @CreatedUser,
        0
    );

    SELECT TOP 1 CAST(Id_NV AS NUMERIC(18,0)) AS NewId
    FROM @NewIds;
END
GO


-- 5. STORED PROCEDURE CẬP NHẬT NHÂN VIÊN
CREATE OR ALTER PROCEDURE dbo.sp_Tbl_Nhanvien_Update
    @Id_NV NUMERIC(18,0),
    @MaNV NVARCHAR(50),
    @I_Holot VARBINARY(MAX) = NULL,
    @I_Ten VARBINARY(MAX) = NULL,
    @I_CMND VARBINARY(512) = NULL,
    @CMNDHash VARBINARY(32) = NULL,
    @Ngaysinh DATETIME = NULL,
    @Mobile VARCHAR(20) = NULL,
    @Email NVARCHAR(255) = NULL,
    @I_Sotaikhoan VARBINARY(512) = NULL,
    @SotaikhoanHash VARBINARY(32) = NULL,
    @LastModifiedUser NUMERIC(18,0) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Tbl_Nhanvien
    SET
        MaNV = NULLIF(@MaNV, ''),
        Holot = NULL,
        Ten = NULL,
        I_Holot = @I_Holot,
        I_Ten = @I_Ten,
        CMND = NULL,
        I_CMND = @I_CMND,
        CMNDHash = @CMNDHash,
        I_Sotaikhoan = @I_Sotaikhoan,
        SotaikhoanHash = @SotaikhoanHash,
        Ngaysinh = @Ngaysinh,
        Mobile = NULLIF(@Mobile, ''),
        Email = NULLIF(@Email, ''),
        LastModified = GETDATE(),
        LastModifiedUser = @LastModifiedUser
    WHERE Id_NV = @Id_NV
      AND ISNULL(Disable, 0) = 0;
END
GO


-- 6. STORED PROCEDURE LẤY DỮ LIỆU MÃ HÓA THEO DANH SÁCH ID
CREATE OR ALTER PROCEDURE dbo.sp_Tbl_Nhanvien_GetByIds
    @Ids NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        Id_NV,
        MaNV,
        I_Holot,
        I_Ten,
        I_CMND,
        I_Sotaikhoan,
        Mobile,
        Email,
        Ngaysinh,
        Phai,
        Disable,
        DateCreated,
        LastModified
    FROM dbo.Tbl_Nhanvien
    WHERE ISNULL(Disable, 0) = 0
      AND Id_NV IN
      (
          SELECT TRY_CAST(LTRIM(RTRIM(value)) AS NUMERIC(18,0))
          FROM STRING_SPLIT(@Ids, ',')
          WHERE LTRIM(RTRIM(value)) <> ''
      );
END
GO


-- 7. STORED PROCEDURE LẤY TOÀN BỘ DỮ LIỆU MÃ HÓA
CREATE OR ALTER PROCEDURE dbo.sp_Tbl_Nhanvien_GetAllEncrypted
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        Id_NV,
        MaNV,
        I_Holot,
        I_Ten,
        I_CMND,
        I_Sotaikhoan,
        Mobile,
        Email,
        Ngaysinh,
        Phai,
        Disable,
        DateCreated,
        LastModified
    FROM dbo.Tbl_Nhanvien
    WHERE ISNULL(Disable, 0) = 0;
END
GO


-- 8. STORED PROCEDURE TRA CỨU CHÍNH XÁC BẰNG HASH
CREATE OR ALTER PROCEDURE dbo.sp_Tbl_Nhanvien_FindIdsByCMNDHash
    @CMNDHash VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id_NV
    FROM dbo.Tbl_Nhanvien
    WHERE CMNDHash = @CMNDHash
      AND ISNULL(Disable, 0) = 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Tbl_Nhanvien_FindIdsBySotaikhoanHash
    @SotaikhoanHash VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id_NV
    FROM dbo.Tbl_Nhanvien
    WHERE SotaikhoanHash = @SotaikhoanHash
      AND ISNULL(Disable, 0) = 0;
END
GO


-- 9. STORED PROCEDURE THÊM DÒNG SECUREINDEX
CREATE OR ALTER PROCEDURE dbo.sp_SecureIndex_Insert
    @RecordId INT,
    @TableName NVARCHAR(100),
    @ColumnName NVARCHAR(100),
    @GramHash VARBINARY(32),
    @Position INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.SecureIndex
    (
        RecordId,
        TableName,
        ColumnName,
        GramHash,
        Position
    )
    VALUES
    (
        @RecordId,
        @TableName,
        @ColumnName,
        @GramHash,
        @Position
    );
END
GO


-- 10. STORED PROCEDURE XÓA SECUREINDEX THEO MỘT BẢN GHI
CREATE OR ALTER PROCEDURE dbo.sp_SecureIndex_DeleteByRecord
    @RecordId INT,
    @TableName NVARCHAR(100),
    @ColumnName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.SecureIndex
    WHERE RecordId = @RecordId
      AND TableName = @TableName
      AND ColumnName = @ColumnName;
END
GO


-- 11. STORED PROCEDURE XÓA SECUREINDEX THEO DANH SÁCH BẢN GHI
CREATE OR ALTER PROCEDURE dbo.sp_SecureIndex_DeleteByRecords
    @TableName NVARCHAR(100),
    @ColumnName NVARCHAR(100),
    @Ids NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.SecureIndex
    WHERE TableName = @TableName
      AND ColumnName = @ColumnName
      AND RecordId IN
      (
          SELECT TRY_CAST(LTRIM(RTRIM(value)) AS INT)
          FROM STRING_SPLIT(@Ids, ',')
          WHERE LTRIM(RTRIM(value)) <> ''
      );
END
GO


-- 12. STORED PROCEDURE TÌM TẬP ỨNG VIÊN BẰNG SECUREINDEX
CREATE OR ALTER PROCEDURE dbo.sp_SecureIndex_SearchCandidates
    @TableName NVARCHAR(100),
    @ColumnName NVARCHAR(100),
    @GramHashes dbo.VarbinaryHashList READONLY,
    @MinMatch INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT si.RecordId
    FROM dbo.SecureIndex si
    INNER JOIN @GramHashes gh
        ON si.GramHash = gh.HashValue
    WHERE si.TableName = @TableName
      AND si.ColumnName = @ColumnName
    GROUP BY si.RecordId
    HAVING COUNT(DISTINCT si.GramHash) >= @MinMatch;
END
GO


-- 13. VIEW PUBLIC CHO NGƯỜI DÙNG THÔNG THƯỜNG
CREATE OR ALTER VIEW dbo.vw_Tbl_Nhanvien_Public
AS
SELECT
    Id_NV,
    MaNV,
    CAST(NULL AS NVARCHAR(200)) AS Holot,
    CAST(NULL AS NVARCHAR(100)) AS Ten,
    CAST(NULL AS NVARCHAR(50)) AS CMND,
    Mobile,
    Email,
    N'****' AS Sotaikhoan,
    Ngaysinh,
    DateCreated,
    LastModified,
    Disable
FROM dbo.Tbl_Nhanvien
WHERE ISNULL(Disable, 0) = 0;
GO


-- 14. MIGRATE DỮ LIỆU
CREATE OR ALTER PROCEDURE dbo.sp_Tbl_Nhanvien_MigrateEncrypted
    @Id_NV NUMERIC(18,0),
    @I_Holot VARBINARY(MAX) = NULL,
    @I_Ten VARBINARY(MAX) = NULL,
    @I_CMND VARBINARY(512) = NULL,
    @CMNDHash VARBINARY(32) = NULL,
    @I_Sotaikhoan VARBINARY(512) = NULL,
    @SotaikhoanHash VARBINARY(32) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Tbl_Nhanvien
    SET
        I_Holot = COALESCE(@I_Holot, I_Holot),
        I_Ten = COALESCE(@I_Ten, I_Ten),
        I_CMND = COALESCE(@I_CMND, I_CMND),
        CMNDHash = COALESCE(@CMNDHash, CMNDHash),
        I_Sotaikhoan = COALESCE(@I_Sotaikhoan, I_Sotaikhoan),
        SotaikhoanHash = COALESCE(@SotaikhoanHash, SotaikhoanHash),
        LastModified = GETDATE()
    WHERE Id_NV = @Id_NV;
END
GO


-- 15. XÓA DỮ LIỆU PLAINTEXT CŨ
-- Chỉ chạy sau khi:
-- 1. Đã migrate dữ liệu xong
-- 2. GET private decrypt đúng
-- 3. Search private chạy đúng
-- 4. SecureIndex đã rebuild đầy đủ

/*
UPDATE dbo.Tbl_Nhanvien
SET
    Holot = NULL,
    Ten = NULL,
    CMND = NULL
WHERE Holot IS NOT NULL
   OR Ten IS NOT NULL
   OR CMND IS NOT NULL;
GO
*/