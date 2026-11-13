local addonName, ns = ...

-- The About tab: what Temper is and what it promises, how to get the most
-- from it, plain answers to the questions it tends to raise, its commands,
-- and the small print. One page that scrolls, set out in the same boxed
-- sections as every other page (see Kit.Section), under a box with the
-- logo in it and the button for reporting a problem.
--
-- Nothing on it changes while it's open, so its pieces are made once. It's
-- laid out each time it's shown, all the same: text measured while its
-- frame is still hidden can come back the wrong height, and getting it
-- right once it's on screen costs nothing.
--
-- The answers are about what the addon really does and what the game won't
-- tell it. When either changes, so should they.

local AboutTab = {}
ns.AboutTab = AboutTab

local Kit = ns.Kit

local LOGO = "Interface\\AddOns\\Temper\\Media\\logo"

-- The game's own marker for a point in a list, as its gossip window uses.
local BULLET = "Interface\\QuestFrame\\UI-Quest-BulletPoint"

-- Space between the tab's edge and the page, and the room kept clear down
-- the right-hand side for the scroll bar, as on the Healing page.
local MARGIN = 14
local TOP_MARGIN = 10
local SCROLL_BAR_ROOM = 24

-- How wide the page is when the window is its usual size. Only used if
-- the tab is laid out before the game has worked out its real width.
local USUAL_WIDTH = 852

-- The logo is twice as wide as it is tall, with clear space above and
-- below the badge, and the words sit this far to the right of it.
local LOGO_WIDTH = 288
local LOGO_HEIGHT = 144
local LOGO_GAP = 18

local BUTTON_WIDTH = 150
local BUTTON_HEIGHT = 22

-- Space between paragraphs, between the points of a list, between one
-- question and the next, and between a question and its answer.
local PARAGRAPH_GAP = 8
local POINT_GAP = 7
local QUESTION_GAP = 12
local ANSWER_GAP = 3

-- A point starts this far in, clear of its marker.
local BULLET_SIZE = 14
local POINT_INDENT = 18

-- How wide the column of commands is, beside what each one does.
local COMMAND_WIDTH = 150

-- What the page says ------------------------------------------------------------

--- A point that opens with a few words in gold, so a list of them can be
--- skimmed by those words alone.
local function Lead(lead, rest)
    return Kit.Colored(lead, Kit.GOLD) .. " " .. rest
end

local PITCH = {
    "Understand your own damage: where it comes from, what's holding it back, and "
        .. "whether a change helped.",
    "Temper records each fight you fight on your own, and keeps it on this computer. "
        .. "Nothing is shared or posted.",
    "Type /temper to open it, or click the fight panel.",
}

-- Each section is a title and what goes in its box: `intro` paragraphs,
-- then `points` with a marker each, then `questions` as { question,
-- answer }, then `commands` as { command, what it does }, then `text`
-- paragraphs to close. Any of them can be left out.
local function Sections()
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"

    return {
        {
            title = "What it's for",
            intro = {
                "Temper is for understanding your own fighting: how much damage you do, how "
                    .. "it's done, what's getting in its way, and how well you keep yourself "
                    .. "going. It says in plain words what might help. It makes four promises.",
            },
            points = {
                Lead(
                    "It's about you.",
                    "It looks at your own damage, healing and defence, and nobody else's."
                ),
                Lead(
                    "It judges no one.",
                    "It isn't a meter for ranking a group and it doesn't measure other "
                        .. "players. In a group it steps aside: no numbers and no record."
                ),
                Lead(
                    "Nothing leaves your game.",
                    "It never posts to chat, never sends anything to other players or to "
                        .. "any server, and has no share or export button. Your fights are "
                        .. "kept in your own saved game data."
                ),
                Lead(
                    "It gives you data to choose with.",
                    "It shows what the figures say and suggests what to try. The choices "
                        .. "are yours."
                ),
            },
        },
        {
            title = "Getting the most from it",
            points = {
                Lead(
                    "Fight.",
                    "There's nothing to set up. Fight something on your own, and the panel "
                        .. "shows the fight as it goes and its exact figures once it's over. "
                        .. "Every solo fight is kept."
                ),
                Lead(
                    "Read a fight.",
                    "Click the panel, or type /temper, and pick a fight on the Fights tab. "
                        .. "Each ability gets a bar, a strip shows what you used in order, and "
                        .. "What to work on says what held your damage back. Rest the mouse on "
                        .. "any figure for what's behind it."
                ),
                Lead(
                    "Sessions and comparing.",
                    "Start session, the stopwatch on the panel, marks a run of fights to "
                        .. "select with one click. To compare, select some fights, press "
                        .. "Compare with..., click the ones to set them against and press "
                        .. "Done. The older set is always the before, so green means you "
                        .. "improved."
                ),
                Lead(
                    "Experiments.",
                    'For a straight answer to "is this better?", press New experiment on '
                        .. "the Experiments tab and follow its three steps. The panel says "
                        .. "when it's your move, and the verdict says how far to trust it."
                ),
                Lead(
                    "Healing and defence.",
                    "The second tab shows what you healed, what hurt you, and about how much "
                        .. "your armour, dodges and shield stopped, for the last fight, the "
                        .. "session or more."
                ),
                Lead(
                    "The panels.",
                    "Drag the fight panel wherever suits, and right-click it for its menu: "
                        .. "what it shows, a normal or a large size, and a healing panel to sit "
                        .. "beside it. An alert below the middle of the screen, off to begin "
                        .. "with, shows an ability the moment it's worth pressing."
                ),
                Lead(
                    "The options.",
                    "The cog on the panel, or in this window's title bar, opens Temper's page "
                        .. "in the game's Options. While it's open, an example enemy shows what "
                        .. "your numbers will look like as you change them."
                ),
            },
        },
        {
            title = "Questions",
            questions = {
                {
                    'Why are my biggest hits only "about"?',
                    "The game hides how hard each blow lands. Temper works it out from how "
                        .. "far the enemy's threat towards you rises with each one, which "
                        .. "follows your damage closely. Blows that land close together come "
                        .. "as one step, so not every blow can be sized.",
                },
                {
                    "Why do the figures change when a fight ends?",
                    "During a fight the game lets Temper show your running damage but not "
                        .. "read it. The exact figures come from the game's own tally, which "
                        .. "it hands over the moment the fight is over.",
                },
                {
                    "Why does nothing show in a group?",
                    "In a group the game doesn't say whose blow was whose, so any figure "
                        .. "would be a guess about other people. Temper steps aside instead: no "
                        .. "numbers of its own and no record, and the game's own numbers come "
                        .. "back. The ability alert and the combo points still show, since "
                        .. "they're only about your own next move.",
                },
                {
                    "Why are my numbers in the middle of the screen?",
                    "They follow each enemy's nameplate, and enemy nameplates are switched "
                        .. "off. Turn them on, in the game's options or with its nameplate key, "
                        .. "and each enemy gets a column of its own.",
                },
                {
                    "Why are some numbers grey and set apart?",
                    "Those are blows Temper takes to be somebody else's: on an enemy that "
                        .. "isn't fighting you, when you hadn't just swung or cast. The game "
                        .. "doesn't say who struck them. They're never counted in your figures, "
                        .. "and the options can hide them or show them like your own.",
                },
                {
                    "Why did an alert come without a sound?",
                    "In a fight the game keeps some buffs from addons, Clearcasting among "
                        .. "them. Temper lets the game's own buff display draw those in the "
                        .. "alert's place, so they still show, but it never learns they came "
                        .. "up and so can't play a sound for them.",
                },
                {
                    'Why does "healed back" count only healing on me?',
                    "It weighs the healing that landed on you, yours and anyone else's, "
                        .. "against the damage you took. Healing spent on your pet or on "
                        .. "someone else undid none of that, so it counts towards what you "
                        .. "healed but not here.",
                },
                {
                    "Why do older fights have no healing, or no enemy level?",
                    "Temper began keeping those later than the damage. A fight only holds "
                        .. "what was being recorded when it was fought, so an older one is "
                        .. "shown without them rather than with a guess.",
                },
                {
                    "Why isn't the typical DPS the plain average?",
                    "It's meant to show how you usually do. It leaves out fights that don't "
                        .. "count, fights against critters and enemies too far below you to "
                        .. "give experience, and, from three fights up, the highest and lowest. "
                        .. "Rest the mouse on it to see how many fights it went by.",
                },
                {
                    "Does Temper send anything anywhere?",
                    "No. It never posts, never talks to other players' addons and never "
                        .. "reaches a server. Report a problem only fills a box for you to "
                        .. "copy yourself, and you can read every word of it first.",
                },
                {
                    "How do I forget everything?",
                    "Press Forget everything at the bottom of the Progress tab. After asking, "
                        .. "it deletes every fight, session and experiment kept for this "
                        .. "character. A single fight can be deleted from the Fights tab with "
                        .. "a right-click.",
                },
                {
                    "What is /temper check for?",
                    "It prints a few lines on how Temper is getting on with the game: how "
                        .. "many fights are on record, whether your numbers are finding "
                        .. "nameplates, which of your class's alerts it can watch, and anything "
                        .. "the game refused. The same lines go into a problem report.",
                },
            },
        },
        {
            title = "Commands",
            commands = {
                { "/temper", "Opens or closes this window." },
                { "/temper session", "Starts a session, or ends the one that's running." },
                { "/temper options", "Opens Temper's page in the game's Options." },
                { "/temper example", "Shows or hides the example enemy with made-up hits." },
                { "/temper check", "Says in chat how Temper is getting on with the game." },
                { "/temper report", "Opens a problem report, ready to copy." },
            },
            text = {
                "Starting and ending a session can also have a key of its own, under Options, "
                    .. "Keybindings, Temper.",
            },
        },
        {
            title = "Something wrong, or an idea?",
            text = {
                "Press Report a problem at the top of this page, or type /temper report. It "
                    .. "gathers what's needed to track a fault down (versions, your settings, "
                    .. "what /temper check says and which other combat addons are loaded) into "
                    .. "a box you can copy, and says where to paste it. It includes no "
                    .. "character names and no realm.",
                "Ideas are welcome at the same address.",
            },
        },
        {
            title = "The small print",
            text = {
                "Temper "
                    .. version
                    .. ", made under the Flight Path Labs name and shared "
                    .. "under the MIT licence.",
                "It was made with the help of an AI model, used openly alongside "
                    .. "hand-written code. Every part of it is reviewed, and tested in the "
                    .. "game, before it's released.",
                "Temper is a fan-made addon. World of Warcraft and related names and artwork "
                    .. "are trademarks of Blizzard Entertainment. This project is not "
                    .. "affiliated with or endorsed by Blizzard Entertainment.",
            },
        },
    }
end

-- Making the pieces -----------------------------------------------------------

local tab

--- A point in a list: the game's marker, and the words beside it.
local function CreatePoint(section, words)
    local row = CreateFrame("Frame", nil, section)

    local bullet = row:CreateTexture(nil, "ARTWORK")
    bullet:SetSize(BULLET_SIZE, BULLET_SIZE)
    bullet:SetPoint("TOPLEFT", -3, 1)
    bullet:SetTexture(BULLET)

    row.indent = POINT_INDENT
    row.text = Kit.Paragraph(row, "GameFontHighlight")
    row.text:SetPoint("TOPLEFT", row.indent, 0)
    row.text:SetText(words)

    return row
end

--- A command in gold, and what it does beside it.
local function CreateCommand(section, command, what)
    local row = CreateFrame("Frame", nil, section)

    row.command = Kit.Text(row, "GameFontNormal")
    row.command:SetPoint("TOPLEFT")
    row.command:SetText(command)

    row.indent = COMMAND_WIDTH
    row.text = Kit.Paragraph(row, "GameFontHighlight")
    row.text:SetPoint("TOPLEFT", row.indent, 0)
    row.text:SetText(what)

    return row
end

--- The pieces of one section, in the order they go down it. Each is
--- { kind, piece, words, gap }: what sort of piece it is, the piece, the
--- words for text that's placed as it wraps, and the space above it.
local function CreateSection(page, definition)
    local section = Kit.Section(page, definition.title)
    local pieces = {}

    -- The first piece in a box sits straight under its title band. The
    -- rest leave the gap their kind wants.
    local function Add(kind, piece, words, gap)
        table.insert(pieces, {
            kind = kind,
            piece = piece,
            words = words,
            gap = #pieces == 0 and 0 or gap,
        })
    end

    local function Paragraphs(list)
        for _, words in ipairs(list or {}) do
            Add("text", Kit.Paragraph(section, "GameFontHighlight"), words, PARAGRAPH_GAP)
        end
    end

    Paragraphs(definition.intro)
    for _, words in ipairs(definition.points or {}) do
        Add("row", CreatePoint(section, words), nil, POINT_GAP)
    end
    for _, pair in ipairs(definition.questions or {}) do
        Add("text", Kit.Paragraph(section, "GameFontNormal"), pair[1], QUESTION_GAP)
        Add("text", Kit.Paragraph(section, "GameFontHighlight"), pair[2], ANSWER_GAP)
    end
    for _, pair in ipairs(definition.commands or {}) do
        Add("row", CreateCommand(section, pair[1], pair[2]), nil, POINT_GAP)
    end
    Paragraphs(definition.text)

    return { section = section, pieces = pieces }
end

--- The box at the top: the logo, and beside it the version, a few words on
--- what Temper is, and the button for reporting a problem.
local function CreateMasthead(page)
    local head = Kit.Box(page)

    head.logo = head:CreateTexture(nil, "ARTWORK")
    head.logo:SetSize(LOGO_WIDTH, LOGO_HEIGHT)
    head.logo:SetPoint("LEFT", Kit.SECTION_PADDING, 0)
    head.logo:SetTexture(LOGO)

    -- The words go in a frame of their own, so that however many lines
    -- they wrap to, they can be stood level with the middle of the logo.
    local words = CreateFrame("Frame", nil, head)
    words:SetPoint("LEFT", head.logo, "RIGHT", LOGO_GAP, 0)
    head.words = words

    head.version = Kit.Text(words, "GameFontDisableSmall")
    head.version:SetPoint("TOPLEFT")
    head.version:SetText("Version " .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))

    head.pitch = Kit.Paragraph(words, "GameFontHighlight")
    head.pitch:SetPoint("TOPLEFT", head.version, "BOTTOMLEFT", 0, -6)
    head.pitch:SetText(table.concat(PITCH, "\n\n"))

    local report = Kit.Button(words, "Report a problem", BUTTON_WIDTH, function()
        ns.ShowReport()
    end)
    report:SetPoint("BOTTOMLEFT")
    Kit.Tooltip(report, "Report a problem", function()
        return {
            "Gathers what's needed to track a fault down into a box you can copy, and "
                .. "says where to paste it. Nothing is sent from the game.",
        }
    end)

    return head
end

-- Laying it out ---------------------------------------------------------------

local function PageWidth()
    local width = tab.scroll:GetWidth()
    return width > 0 and width or USUAL_WIDTH
end

local function PlaceMasthead(layout)
    local head = tab.masthead
    local wordsWidth = layout.width - 2 * Kit.SECTION_PADDING - LOGO_WIDTH - LOGO_GAP

    head.pitch:SetWidth(wordsWidth)
    local wordsHeight = head.version:GetStringHeight()
        + 6
        + head.pitch:GetStringHeight()
        + 14
        + BUTTON_HEIGHT
    head.words:SetSize(wordsWidth, wordsHeight)

    local height = math.max(LOGO_HEIGHT, wordsHeight) + 2 * Kit.SECTION_PADDING
    head:SetHeight(height)
    Kit.Place(layout, head, 0, height)
end

local function PlaceSection(layout, built)
    local inside = Kit.Inside(layout, built.section)

    for _, item in ipairs(built.pieces) do
        if item.kind == "text" then
            Kit.PlaceText(inside, item.piece, item.gap, item.words)
        else
            -- A row is as tall as its words wrap to, in the width left
            -- beside its marker or its command.
            local row = item.piece
            row.text:SetWidth(inside.width - row.indent)
            row:SetHeight(row.text:GetStringHeight())
            Kit.Place(inside, row, item.gap)
        end
    end

    Kit.PlaceSection(layout, built.section, inside)
end

local function Refresh()
    if not tab or not tab:IsVisible() then
        return
    end

    local width = PageWidth()
    local layout = { frame = tab.page, left = 0, width = width, y = 0 }

    PlaceMasthead(layout)
    for _, built in ipairs(tab.sections) do
        PlaceSection(layout, built)
    end

    -- The scroll range comes from the page's height, which has to be set
    -- by hand.
    tab.page:SetSize(width, layout.y + Kit.SECTION_GAP)
end

--- Builds the tab.
---@param parent table  the window's inset, which the tab fills
function AboutTab.Create(parent)
    tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()

    -- The template brings its own scroll bar, which only needs telling to
    -- stay out of sight while everything fits.
    tab.scroll = CreateFrame("ScrollFrame", nil, tab, "ScrollFrameTemplate")
    tab.scroll:SetPoint("TOPLEFT", MARGIN, -TOP_MARGIN)
    tab.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_ROOM, 8)
    tab.scroll.ScrollBar:SetHideIfUnscrollable(true)

    tab.page = CreateFrame("Frame", nil, tab.scroll)
    tab.page:SetSize(USUAL_WIDTH, 1)
    tab.scroll:SetScrollChild(tab.page)

    tab.masthead = CreateMasthead(tab.page)
    tab.sections = {}
    for _, definition in ipairs(Sections()) do
        table.insert(tab.sections, CreateSection(tab.page, definition))
    end

    tab.Refresh = Refresh
    return tab
end
