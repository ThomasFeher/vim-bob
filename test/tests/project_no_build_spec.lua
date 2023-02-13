describe("BobProjectNoBuild", function()
	before_each(function()
		vim.fn.delete("./dev", "rf") -- better vim.loop.fs_rmdir
		vim.cmd("BobInit")
	end)
	it("should run successfully if BobDev was called before", function()
		-- using the bang variant here, because otherwise :make tries to open a file "Duration: 0" which is the first part of Bob's last output line, TODO we need to avoid that somehow, e.g., by modifying errorformat option
		-- vim.cmd("echoerr 'test'")
		vim.cmd("BobDev! app_a")
		vim.cmd("BobProjectNoBuild app_a")
	end)
end)
