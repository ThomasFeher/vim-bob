-- describe("BobProject", function()
-- 	it("should fail if uninitialized", function()
-- 		-- How to catch excepions thrown from vimscript here?
-- 	end)
-- end)
describe("BobProject", function()
	before_each(function()
		vim.fn.delete("./dev", "rf") -- better vim.loop.fs_rmdir
		vim.cmd("messages clear")
		vim.cmd("BobInit")
		vim.g.bob_config_path = "./configurations"
	end)
	it("should copy the compilation database of a standalone application", function()
		-- using the bang variant here, because otherwise :make tries to open a file "Duration: 0" which is the first part of Bob's last output line, TODO we need to avoid that somehow, e.g., by modifying errorformat option
		vim.cmd("BobProject! app_a")
		-- print(vim.loop.cwd())
		-- vim.pretty_print(vim.fn.readdir("dev"))
		local result = table.concat(vim.fn.readfile("./dev/compile_commands.json"), "\n")
		-- local fid = vim.loop.fs_open("./dev/compile_commands.json", "r", 644)
		-- assert(fid, "fid is " .. fid)
		-- print(vim.loop.fs_read(fid, 10))
		local reference = [=[
[
{
  "app_a": "entry 1"
},
{
  "app_a": "entry 2"
}
]]=]
		assert(result == reference, "result:\n" .. result .. "\nreference:\n" .. reference)
	end)
	it("should merge the compilation databases of an application and its library", function()
		-- using the bang variant here, because otherwise :make tries to open a file "Duration: 0" which is the first part of Bob's last output line, TODO we need to avoid that somehow, e.g., by modifying errorformat option
		vim.cmd("BobProject! app_b")
		-- print(vim.loop.cwd())
		-- vim.pretty_print(vim.fn.readdir("dev"))
		local result = table.concat(vim.fn.readfile("./dev/compile_commands.json"), "\n")
		-- local fid = vim.loop.fs_open("./dev/compile_commands.json", "r", 644)
		-- assert(fid, "fid is " .. fid)
		-- print(vim.loop.fs_read(fid, 10))
		local reference = [=[
[
{
  "app_b": "entry 1"
},
{
  "app_b": "entry 2"
}
,
{
  "lib_a": "entry 1"
},
{
  "lib_a": "entry 2"
}
]]=]
		assert(result == reference, "result:\n" .. result .. "\nreference:\n" .. reference)
	end)
	for _, item in ipairs({'-b', '--build-only', '-v', '-vv', '-vvv', '--verbose', '--clean', '--force', '-q','-qq',  '-qqq', "-j", "-j2", "--jobs", '--upload'}) do
		it("should build with flag " .. item .. " given", function()
			-- using the bang variant here, because otherwise :make tries to open a file "Duration: 0" which is the first part of Bob's last output line, TODO we need to avoid that somehow, e.g., by modifying errorformat option
			vim.cmd("BobProject! app_b native " .. item)
			local output = vim.api.nvim_exec2('messages', { output = true }).output
			assert(not string.find(output, "Running Bob failed."), output)
		end)
	end
	it("should ignore packages that do not create src or build directories", function()
		-- using the bang variant here, because otherwise :make tries to open a file "Duration: 0" which is the first part of Bob's last output line, TODO we need to avoid that somehow, e.g., by modifying errorformat option
		vim.cmd("BobProject! app_c")
		local output = vim.api.nvim_exec2('messages', { output = true }).output
		assert(string.find(output, "ignoring package lib_empty"))
	end)
end)
