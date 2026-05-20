local function read_file(path)
	local handle = assert(io.open(path, "r"))
	local source = assert(handle:read("*a"))
	handle:close()
	return source
end

describe("release script", function()
	it("waits for CI to attach the package before falling back to local upload", function()
		local source = read_file("scripts/release.sh")

		local wait_pos = assert(source:find("Waiting for $PACKAGE_ASSET from CI", 1, true))
		local fallback_pos = assert(source:find("CI did not attach $PACKAGE_ASSET", 1, true))

		assert.is_true(wait_pos < fallback_pos)
	end)

	it("treats duplicate package upload as success only after the asset exists", function()
		local source = read_file("scripts/release.sh")

		assert.is_truthy(source:find("ReleaseAsset.name already exists", 1, true))
		assert.is_truthy(source:find("release_asset_exists", 1, true))
		assert.is_truthy(source:find("appeared during upload fallback", 1, true))
	end)
end)
