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

	it("validates the VERSION argument format before doing any work", function()
		local source = read_file("scripts/release.sh")

		assert.is_truthy(source:find("VERSION must be X.Y.Z", 1, true))
	end)

	it("aborts with a clear error when CI never creates the release", function()
		local source = read_file("scripts/release.sh")

		local create_wait_pos = assert(source:find("Waiting for GitHub release to be created by CI", 1, true))
		local abort_pos =
			assert(source:find("CI did not create release", 1, true), "missing early abort after release-creation wait")
		local asset_wait_pos = assert(source:find("Waiting for $PACKAGE_ASSET from CI", 1, true))

		assert.is_true(create_wait_pos < abort_pos)
		assert.is_true(abort_pos < asset_wait_pos)
	end)

	it("treats duplicate package upload as success only after the asset exists", function()
		local source = read_file("scripts/release.sh")

		assert.is_truthy(source:find("ReleaseAsset.name already exists", 1, true))
		assert.is_truthy(source:find("release_asset_exists", 1, true))
		assert.is_truthy(source:find("appeared during upload fallback", 1, true))
	end)
end)
