local M = {}

-- テーブル内に指定したキーが含まれているか確認
function M.is_exist_key(key, tbl)
	for k, v in pairs(tbl) do
		if k == key then
			return true
		elseif type(v) == "table" and M.is_exist_key(key, v) then
			return true
		end
	end
	return false
end

-- テーブル内の指定したキーが格納されている要素番号を返す
function M.search_table(key, tbl)
	for i, v in pairs(tbl) do
		if type(v) == "table" and v[key] ~= nil then
			return i
		elseif type(v) == "table" then
			local result = M.search_table(v)
			if result ~= nil then
				return result
			end
		end
	end
	return nil
end

return M
