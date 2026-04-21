# SQL 參數清理工具 說明文件

檔案：`sql_cleaner.html`  
使用方式：直接用瀏覽器開啟，不需安裝任何環境。

---

## 功能概覽

| 按鈕 | 方向 | 用途 |
|------|------|------|
| ▶ 轉換 | 原始 → 可執行 SQL | 處理報表工具參數、Java 程式碼、IN_ 參數 → 純 SQL |
| ↩ 反向轉換 | 可執行 SQL → 原始格式 | `:param` → `{?param}`；`:IN_SETYEAR` → `IN_SETYEAR` |
| ✕ 清除 | — | 清空左右兩側所有內容 |
| ⎘ 複製結果 | — | 複製右側清理後的 SQL 到剪貼簿 |

---

## 支援的輸入格式

### 格式一：報表工具參數 `{?param}`

報表工具（如 JasperReport、BIRT 等）使用 `{?參數名稱}` 作為參數占位符。

**輸入範例**
```sql
SELECT *
FROM policy.target_org t1
WHERE t1.type = CASE
    WHEN {?parm_half} = '0' THEN {?parm_year} || 'empbase'
    ELSE {?parm_year} || 'empbaseH' || {?parm_half}
END
AND t1.org = DECODE({?parm_org}, 'all', t1.org, {?parm_org})
```

**▶ 轉換後**
```sql
SELECT *
FROM policy.target_org t1
WHERE t1.type = CASE
    WHEN :parm_half = '0' THEN :parm_year || 'empbase'
    ELSE :parm_year || 'empbaseH' || :parm_half
END
AND t1.org = DECODE(:parm_org, 'all', t1.org, :parm_org)
```

---

### 格式二：Java `sbSql.append("...");`

Java 開發常見的 `StringBuffer` 或 `StringBuilder` 拼接 SQL 寫法。

**輸入範例**
```java
sbSql.append(" SELECT DISTINCT setyear yy ");
sbSql.append(" FROM policy.race_cal_setup  ");
sbSql.append(" WHERE settype = 'PCRSYFM'  ");
sbSql.append(" AND TO_CHAR(SYSDATE,'YYYYMMDD') BETWEEN SHOW_DTS AND SHOW_DTE ");
sbSql.append(" ORDER BY setyear DESC ");
```

**▶ 轉換後**
```sql
SELECT DISTINCT setyear yy
FROM policy.race_cal_setup
WHERE settype = 'PCRSYFM'
AND TO_CHAR(SYSDATE,'YYYYMMDD') BETWEEN SHOW_DTS AND SHOW_DTE
ORDER BY setyear DESC
```

> **備註**：若 `append` 中包含 Java 變數串接（如 `+ varName +`），該變數會自動轉為 `{?varName}`，再由後續替換邏輯轉成 `:varName`。

---

### 格式三：Java 字串拼接 `"..." + "..."`

另一種 Java 常見寫法，每行為一個帶引號的字串片段，以 `+` 串接。  
支援兩種起始方式：純引號開頭、或附有 Java 變數宣告（`String sql = "..."`）。

**輸入範例 A：純引號開頭**
```java
"WHEN p.rec_type = 'D' AND SUBSTR(NVL(p.status_no,'00'),1,1) <> '0' THEN '3' "
    + "ELSE '5' "
    + "END ssort "
    + "FROM policy.POLICYSTATUS_WITH_KINDACCEPT p "
    + "WHERE 1=1 "
    + "AND nvl(kind_acceptdt, nvl(ddue_dt, due_dt)) BETWEEN :symd AND :eymd "
    + "AND from_dt BETWEEN SUBSTR(:symd,0,6) AND SUBSTR(:eymd,0,6) ";
```

**輸入範例 B：Java 變數宣告開頭**
```java
String sql = "SELECT l.code_name org, p.eno, e.ename "
    + "FROM shen.poldtl_hv p, shen.employee e "
    + "WHERE p.eno = e.eno "
    + "AND (p.eno = :parm_eno OR NVL(:parm_eno,'all') = 'all') "
    + "AND p.kind_acceptdt BETWEEN :parm_dts AND :parm_dte "
    + "ORDER BY p.eno ";
```

**▶ 轉換後（兩種寫法結果相同）**
```sql
WHEN p.rec_type = 'D' AND SUBSTR(NVL(p.status_no,'00'),1,1) <> '0' THEN '3' 
ELSE '5' 
END ssort 
FROM policy.POLICYSTATUS_WITH_KINDACCEPT p 
WHERE 1=1 
AND nvl(kind_acceptdt, nvl(ddue_dt, due_dt)) BETWEEN :symd AND :eymd 
AND from_dt BETWEEN SUBSTR(:symd,0,6) AND SUBSTR(:eymd,0,6)
```

> **備註**：起始行的 Java 型別與變數名稱（如 `String sql =`、`String strSql =`）會自動略過，只保留引號內的 SQL 內容。

---

### 格式四：Oracle Bind Variable `:param`（反向轉換）

已是可執行的 SQL，想貼回報表工具時使用「↩ 反向轉換」。

**輸入範例**
```sql
SELECT *
FROM policy.target_org
WHERE org = :parm_org
AND type LIKE :parm_year || '%'
```

**↩ 反向轉換後**
```sql
SELECT *
FROM policy.target_org
WHERE org = {?parm_org}
AND type LIKE {?parm_year} || '%'
```

---

### 格式五：預存程序 `IN_` 參數

Oracle 預存程序（Stored Procedure）常以 `IN_` 開頭的全大寫識別字作為輸入參數，直接出現在 SQL 本文中。

**輸入範例**
```sql
SELECT policy.SEQ_REWARD_PLAN_BONUS.nextval, IN_REWARD_PLAN, IN_RTYPE, m.eno
FROM POLICY.REWARD_PLAN_SCORE m
LEFT JOIN POLICY.REWARD_PLAN_SCORE s1
    ON s1.rtype = IN_SETYEAR || '_5335_H' || IN_SETNO
WHERE m.reward_plan = IN_REWARD_PLAN
  AND m.rtype = IN_RTYPE;
```

**▶ 轉換後**
```sql
SELECT policy.SEQ_REWARD_PLAN_BONUS.nextval, :IN_REWARD_PLAN, :IN_RTYPE, m.eno
FROM POLICY.REWARD_PLAN_SCORE m
LEFT JOIN POLICY.REWARD_PLAN_SCORE s1
    ON s1.rtype = :IN_SETYEAR || '_5335_H' || :IN_SETNO
WHERE m.reward_plan = :IN_REWARD_PLAN
  AND m.rtype = :IN_RTYPE;
```

**↩ 反向轉換後**（從可執行 SQL 還原）
```sql
SELECT policy.SEQ_REWARD_PLAN_BONUS.nextval, IN_REWARD_PLAN, IN_RTYPE, m.eno
...
WHERE m.reward_plan = IN_REWARD_PLAN
  AND m.rtype = IN_RTYPE;
```

> **識別規則**：`IN_` 開頭且後續全為大寫字母、數字、底線（如 `IN_SETYEAR`、`IN_SETNO`、`IN_REWARD_PLAN`）。  
> 小寫欄位別名（如 `p.INV_TYPE`）不符合條件，不會被誤判。

---

## 混合格式

五種格式可以**同時混貼**，工具會依序處理：

1. 先解析 Java 字串拼接 `"..." + "..."`
2. 再解析 `sbSql.append("...")`
3. 將所有 `{?param}` 替換為 `:param`
4. 將所有 `IN_` 開頭全大寫識別字替換為 `:IN_XXX`

---

## 操作流程

### 正向轉換（複製到 DB 工具執行）

1. 從 Java 程式碼或報表工具複製 SQL
2. 貼入左側「貼入原始 SQL」區域
3. 點擊「**▶ 轉換**」
4. 右側出現可直接執行的 SQL
5. 點擊「**⎘ 複製結果**」貼到 SQL 開發工具（如 SQLcl、DBeaver、SQL Developer）執行

### 反向轉換（複製回報表工具 / 預存程序）

1. 將已調整好的可執行 SQL 貼入左側
2. 點擊「**↩ 反向轉換**」
3. `:parm_name` 轉回 `{?parm_name}`；`:IN_SETYEAR` 轉回 `IN_SETYEAR`
4. 點擊「**⎘ 複製結果**」貼回報表工具或預存程序

---

## 轉換規則對照表

| 輸入格式 | 輸出格式 | 按鈕 |
|---------|---------|------|
| `{?parm_name}` | `:parm_name` | ▶ 轉換 |
| `sbSql.append(" SQL ");` | 純 SQL 字串 | ▶ 轉換 |
| `"SQL " + "SQL "` | 純 SQL 字串 | ▶ 轉換 |
| `IN_SETYEAR`（全大寫）| `:IN_SETYEAR` | ▶ 轉換 |
| `:parm_name` | `{?parm_name}` | ↩ 反向轉換 |
| `:IN_SETYEAR` | `IN_SETYEAR` | ↩ 反向轉換 |
