-- tests/report_test.lua — run from repo root: lua tests/report_test.lua
local report = dofile("RR Dupe Finder/Scripts/report.lua")

local failures = 0
local function check(name, cond)
    if cond then
        print("PASS: " .. name)
    else
        print("FAIL: " .. name)
        failures = failures + 1
    end
end

-- analyze: empty input
do
    local a = report.analyze({}, 2)
    check("empty totalCarts",     a.totalCarts == 0)
    check("empty uniqueSkus",     a.uniqueSkus == 0)
    check("empty no dupes",       #a.dupes == 0)
    check("empty sellable 0",     a.sellableExtras == 0)
end

-- analyze: all unique → no dupes
do
    local recs = {
        { sku = 1, x = 0, y = 0, z = 0 },
        { sku = 2, x = 0, y = 0, z = 0 },
        { sku = 3, x = 0, y = 0, z = 0 },
    }
    local a = report.analyze(recs, 2)
    check("unique totalCarts",    a.totalCarts == 3)
    check("unique uniqueSkus",    a.uniqueSkus == 3)
    check("unique no dupes",      #a.dupes == 0)
    check("unique sellable 0",    a.sellableExtras == 0)
end

-- analyze: 10 x3, 20 x2, 30 x1 → dupes [10(3), 20(2)], sellable 3
do
    local recs = {
        { sku = 30, x = 0, y = 0, z = 0 },
        { sku = 10, x = 1, y = 2, z = 3 },
        { sku = 20, x = 0, y = 0, z = 0 },
        { sku = 10, x = 4, y = 5, z = 6 },
        { sku = 20, x = 0, y = 0, z = 0 },
        { sku = 10, x = 7, y = 8, z = 9 },
    }
    local a = report.analyze(recs, 2)
    check("mix totalCarts",       a.totalCarts == 6)
    check("mix uniqueSkus",       a.uniqueSkus == 3)
    check("mix dupe count",       #a.dupes == 2)
    check("mix sorted first 10",  a.dupes[1].sku == 10 and a.dupes[1].copies == 3)
    check("mix sorted second 20", a.dupes[2].sku == 20 and a.dupes[2].copies == 2)
    check("mix sellable 3",       a.sellableExtras == 3)
    check("mix locs captured",    #a.dupes[1].locs == 3 and a.dupes[1].locs[1].x == 1)
end

-- analyze: MinCopies = 3 → only 10 flagged
do
    local recs = {
        { sku = 10, x = 0, y = 0, z = 0 }, { sku = 10, x = 0, y = 0, z = 0 }, { sku = 10, x = 0, y = 0, z = 0 },
        { sku = 20, x = 0, y = 0, z = 0 }, { sku = 20, x = 0, y = 0, z = 0 },
    }
    local a = report.analyze(recs, 3)
    check("min3 dupe count",      #a.dupes == 1)
    check("min3 only 10",         a.dupes[1].sku == 10)
    check("min3 sellable 2",      a.sellableExtras == 2)
end

-- analyze: tie-break by sku ascending when copies equal
do
    local recs = {
        { sku = 20, x = 0, y = 0, z = 0 }, { sku = 20, x = 0, y = 0, z = 0 },
        { sku = 10, x = 0, y = 0, z = 0 }, { sku = 10, x = 0, y = 0, z = 0 },
    }
    local a = report.analyze(recs, 2)
    check("tie first 10",         a.dupes[1].sku == 10)
    check("tie second 20",        a.dupes[2].sku == 20)
end

-- format: empty → single "No cassettes found." line
do
    local lines = report.format(report.analyze({}, 2))
    check("fmt empty single line", #lines == 1)
    check("fmt empty text",        lines[1] == "No cassettes found.")
end

-- format: all unique → header + clean line
do
    local recs = { { sku = 1, x = 0, y = 0, z = 0 }, { sku = 2, x = 0, y = 0, z = 0 } }
    local lines = report.format(report.analyze(recs, 2))
    check("fmt clean header",  lines[1] == "Scan complete: 2 cassettes, 2 unique SKUs, 0 duplicated.")
    check("fmt clean line",    lines[2] == "No duplicates — collection is clean.")
end

-- format: dupes → header, per-SKU blocks, footer
do
    local recs = {
        { sku = 10, x = 1, y = 2, z = 3 },
        { sku = 10, x = 4, y = 5, z = 6 },
        { sku = 20, x = 7, y = 8, z = 9 },
        { sku = 20, x = 1, y = 1, z = 1 },
        { sku = 30, x = 0, y = 0, z = 0 },
    }
    local lines = report.format(report.analyze(recs, 2))
    check("fmt dupe header",  lines[1] == "Scan complete: 5 cassettes, 3 unique SKUs, 2 duplicated.")
    check("fmt dupe sku10",   lines[2] == "SKU 10 — 2 copies:")
    check("fmt dupe sku10 c1",lines[3] == "    #1  (1.0, 2.0, 3.0)  <- KEEP this one")
    check("fmt dupe sku10 c2",lines[4] == "    #2  (4.0, 5.0, 6.0)")
    check("fmt dupe sku20",   lines[5] == "SKU 20 — 2 copies:")
    check("fmt dupe footer",  lines[#lines] == "Total sellable extras: 2   (copies minus rented, minus one to keep, per duplicated SKU)")
end

-- v2: title carried onto group + titled header
do
    local recs = {
        { sku = 10, title = "Blade Runner", x = 1, y = 2, z = 3, actor = "A1" },
        { sku = 10, title = "Blade Runner", x = 4, y = 5, z = 6, actor = "A2" },
    }
    local a = report.analyze(recs, 2)
    check("v2 title on group",   a.dupes[1].title == "Blade Runner")
    local lines = report.format(a)
    check("v2 titled header",    lines[2] == '"Blade Runner" (SKU 10) — 2 copies:')
end

-- v2: nil title → bare SKU header (back-compat with v1 records)
do
    local recs = {
        { sku = 20, x = 1, y = 1, z = 1 }, { sku = 20, x = 2, y = 2, z = 2 },
    }
    local lines = report.format(report.analyze(recs, 2))
    check("v2 untitled header",  lines[2] == "SKU 20 — 2 copies:")
end

-- v2: first non-nil title wins even if a later copy lacks one
do
    local recs = {
        { sku = 30, title = nil,         x = 1, y = 1, z = 1 },
        { sku = 30, title = "The Thing", x = 2, y = 2, z = 2 },
    }
    check("v2 first non-nil title", report.analyze(recs, 2).dupes[1].title == "The Thing")
end

-- v2: placed vs backstock flag + epsilon boundary
do
    local recs = {
        { sku = 40, title = "X", x = 0,   y = 0,    z = 0 },  -- origin → backstock
        { sku = 40, title = "X", x = 0.3, y = -0.2, z = 0.1 },-- within eps → backstock
        { sku = 40, title = "X", x = 0.6, y = 0,    z = 0 },  -- outside eps → placed
        { sku = 40, title = "X", x = 100, y = 200,  z = 5 },  -- clearly placed
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("v2 copies==4",        g.copies == 4)
    check("v2 placedCopies==2",  g.placedCopies == 2)
    check("v2 loc1 backstock",   g.locs[1].placed == false)
    check("v2 loc2 eps backstk", g.locs[2].placed == false)
    check("v2 loc3 eps placed",  g.locs[3].placed == true)
    check("v2 loc4 placed",      g.locs[4].placed == true)
end

-- v2: backstock suffix + per-copy lines
do
    local recs = {
        { sku = 50, title = "Alien", x = 10, y = 20, z = 30 }, -- placed
        { sku = 50, title = "Alien", x = 0,  y = 0,  z = 0 },  -- backstock
    }
    local lines = report.format(report.analyze(recs, 2))
    check("v2 suffix header",    lines[2] == '"Alien" (SKU 50) — 2 copies (1 sellable, 1 backstock):')
    check("v2 placed line",      lines[3] == "    #1  (10.0, 20.0, 30.0)  <- KEEP this one")
    check("v2 backstock line",   lines[4] == "    #2  backstock (unplaced)")
end

-- v2: all-placed dupe → no suffix
do
    local recs = {
        { sku = 60, title = "Akira", x = 1, y = 1, z = 1 },
        { sku = 60, title = "Akira", x = 2, y = 2, z = 2 },
    }
    local lines = report.format(report.analyze(recs, 2))
    check("v2 no suffix",        lines[2] == '"Akira" (SKU 60) — 2 copies:')
end

-- v2: actor ref threaded through opaquely (for Session 3's tinting)
do
    local recs = {
        { sku = 70, title = "Heat", x = 1, y = 1, z = 1, actor = "ACT-1" },
        { sku = 70, title = "Heat", x = 2, y = 2, z = 2, actor = "ACT-2" },
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("v2 actor1 carried",   g.locs[1].actor == "ACT-1")
    check("v2 actor2 carried",   g.locs[2].actor == "ACT-2")
end

-- v3: rented copy is bucketed rented (precedence over backstock/sellable) and excluded from extras
do
    local recs = {
        { sku = 80, title = "Jaws", x = 10, y = 10, z = 10, rented = false }, -- sellable
        { sku = 80, title = "Jaws", x = 20, y = 20, z = 20, rented = true  }, -- rented (placed but reserved)
        { sku = 80, title = "Jaws", x = 0,  y = 0,  z = 0,  rented = false }, -- backstock
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("v3 copies==3",         g.copies == 3)
    check("v3 sellableCopies==1", g.sellableCopies == 1)
    check("v3 backstockCopies==1",g.backstockCopies == 1)
    check("v3 rentedCopies==1",   g.rentedCopies == 1)
    check("v3 loc rented flag",   g.locs[2].rented == true)
end

-- v3: full three-bucket suffix + per-copy lines
do
    local recs = {
        { sku = 81, title = "Saw", x = 1, y = 1, z = 1, rented = false }, -- sellable
        { sku = 81, title = "Saw", x = 0, y = 0, z = 0, rented = false }, -- backstock
        { sku = 81, title = "Saw", x = 5, y = 6, z = 7, rented = true  }, -- rented
    }
    local lines = report.format(report.analyze(recs, 2))
    check("v3 3-bucket suffix", lines[2] == '"Saw" (SKU 81) — 3 copies (1 sellable, 1 backstock, 1 rented):')
    check("v3 sellable line",   lines[3] == "    #1  (1.0, 1.0, 1.0)  <- KEEP this one")
    check("v3 backstock line",  lines[4] == "    #2  backstock (unplaced)")
    check("v3 rented line",     lines[5] == "    #3  rented (can't sell)")
end

-- v3: rented subtracted from sellable extras ((copies - rented) - 1)
do
    local recs = {
        { sku = 82, title = "Cube", x = 1, y = 1, z = 1, rented = false },
        { sku = 82, title = "Cube", x = 2, y = 2, z = 2, rented = false },
        { sku = 82, title = "Cube", x = 3, y = 3, z = 3, rented = true  },
    }
    check("v3 extras excl rented", report.analyze(recs, 2).sellableExtras == 1)  -- (3-1)-1 = 1
end

-- v3: back-compat — no `rented` field behaves exactly like v2 (rented treated false)
do
    local recs = {
        { sku = 83, title = "Tron", x = 1, y = 1, z = 1 },
        { sku = 83, title = "Tron", x = 2, y = 2, z = 2 },
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("v3 nil rented == sellable", g.sellableCopies == 2 and g.rentedCopies == 0)
    check("v3 extras back-compat",     report.analyze(recs, 2).sellableExtras == 1)
end

-- v3 keep-one: analyze flags exactly one keeper (first PLACED, non-rented copy) per dupe group
do
    local recs = {
        { sku = 90, title = "E.T.", x = 0,  y = 0,  z = 0,  rented = false }, -- backstock (not keeper)
        { sku = 90, title = "E.T.", x = 11, y = 12, z = 13, rented = false }, -- first placed → KEEPER
        { sku = 90, title = "E.T.", x = 21, y = 22, z = 23, rented = false }, -- placed → sell
    }
    local g = report.analyze(recs, 2).dupes[1]   -- keepOne defaults true
    check("keep loc2 is keeper",  g.locs[2].keep == true)
    check("keep loc1 not keeper", not g.locs[1].keep)
    check("keep loc3 not keeper", not g.locs[3].keep)
    local kept = (g.locs[1].keep and 1 or 0) + (g.locs[2].keep and 1 or 0) + (g.locs[3].keep and 1 or 0)
    check("keep exactly one",     kept == 1)
end

-- v3 keep-one: keeper skips rented + backstock → first PLACED non-rented wins
do
    local recs = {
        { sku = 91, title = "Up", x = 5, y = 5, z = 5, rented = true  }, -- placed but rented (skip)
        { sku = 91, title = "Up", x = 0, y = 0, z = 0, rented = false }, -- backstock (skip)
        { sku = 91, title = "Up", x = 9, y = 9, z = 9, rented = false }, -- first placed non-rented → KEEPER
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("keep skips rented+backstock", g.locs[3].keep == true and not g.locs[1].keep and not g.locs[2].keep)
end

-- v3 keep-one: a SKU with no placed-sellable copy has no keeper (nothing reachable to keep)
do
    local recs = {
        { sku = 92, title = "Wall-E", x = 0, y = 0, z = 0, rented = false }, -- backstock
        { sku = 92, title = "Wall-E", x = 7, y = 7, z = 7, rented = true  }, -- rented
    }
    local g = report.analyze(recs, 2).dupes[1]
    check("keep none when no placed-sellable", not g.locs[1].keep and not g.locs[2].keep)
end

-- v3 keep-one: toggle off (keepOne=false) sets no keeper flags + format stays plain
do
    local recs = {
        { sku = 93, title = "Cars", x = 1, y = 1, z = 1 },
        { sku = 93, title = "Cars", x = 2, y = 2, z = 2 },
    }
    local g = report.analyze(recs, 2, false).dupes[1]
    check("keepOne=false no keeper",  not g.locs[1].keep and not g.locs[2].keep)
    local lines = report.format(report.analyze(recs, 2, false))
    check("keepOne=false plain line", lines[3] == "    #1  (1.0, 1.0, 1.0)")
end

-- v3 keep-one: format annotates only the keeper placed line
do
    local recs = {
        { sku = 94, title = "Brave", x = 1, y = 1, z = 1 }, -- keeper
        { sku = 94, title = "Brave", x = 2, y = 2, z = 2 }, -- sell
    }
    local lines = report.format(report.analyze(recs, 2))  -- keepOne default true
    check("keep fmt keeper line", lines[3] == "    #1  (1.0, 1.0, 1.0)  <- KEEP this one")
    check("keep fmt sell line",   lines[4] == "    #2  (2.0, 2.0, 2.0)")
end

print(string.format("\n%s", failures == 0 and "ALL PASS" or (failures .. " FAILURE(S)")))
os.exit(failures == 0 and 0 or 1)
