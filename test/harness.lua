-- Tiny assert/report framework shared by every qbbusinesses smoke test.
--
-- A failing assertion raises rather than counting, so a broken invariant stops
-- the file it is in instead of cascading misleading failures behind it. run.sh
-- compares the suite header count against the reported count, so a file that
-- dies mid-load is still visible.

local H = { passed = 0, failed = 0, name = 'qbbusinesses' }

function H.equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message or 'values differ', tostring(expected), tostring(actual)), 2)
    end
    H.passed = H.passed + 1
end

function H.ok(value, message) H.equal(not not value, true, message) end
function H.nope(value, message) H.equal(not not value, false, message) end

---Asserts a fallible call returned `(nil|false, err)` rather than a value.
function H.rejects(value, err, message)
    if value then error(('%s: expected a rejection, got %s'):format(message or 'call succeeded', tostring(value)), 2) end
    if type(err) ~= 'string' or err == '' then error(('%s: rejection carried no reason'):format(message or 'call'), 2) end
    H.passed = H.passed + 1
end

function H.finish(suite)
    io.write(('%s: %d passed, %d failed\n'):format(suite or H.name, H.passed, H.failed))
    os.exit(H.failed > 0 and 1 or 0, true)
end

return H
