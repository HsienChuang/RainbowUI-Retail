local AddonName, Data = ...


local MAJOR, MINOR = "LibSpellIconSelector", 3
local LibSpellIconSelector = LibStub:NewLibrary(MAJOR, MINOR)

local C_Spell = C_Spell
local GetSpellInfo = GetSpellInfo

if not LibSpellIconSelector then return end

local frame

local allSpells = nil
local dataProviderTable
local filteredSpells = {}
local selectedIconId
local onApplyF
local deduplicate

local IconSelectorPopupFrameTemplateMixin = IconSelectorPopupFrameTemplateMixin or Data.Mixins.BackportedIconSelectorPopupFrameTemplateMixin

local function deduplicateIcons(t)
	local foundIcons = {}
	local deduplicatedTable = {}
	for i = 1, #t do
		local spell = t[i]
		local spellIcon = spell.icon
		if not foundIcons[spellIcon] then
			table.insert(deduplicatedTable, spell)
			foundIcons[spellIcon] = true
		end
	end
	return deduplicatedTable
end

local function findSpellByIconId(t, iconId)
	for i = 1, #t do
		local spell = t[i]
		local spellIcon = spell.icon
		if spellIcon == iconId then
			return spell
		end
	end
end

local function parseSpellInfo(spellID)
	if C_Spell and C_Spell.GetSpellInfo then
		local spellInfo = C_Spell.GetSpellInfo(spellID)
		if not spellInfo then return end
		if not spellInfo.iconID then return end
		spellInfo.icon = spellInfo.iconID
		return spellInfo
	else
		local name, rank, iconID = GetSpellInfo(spellID)
		if not name or name == "" or not iconID then return end
		return {name = name, spellID = spellID, icon = iconID}
	end
end


local function fetchallSpells()
   local spells = {}

   --highest spellID is almost 400 000 as of 10.0.0.
   local i = 1
   local notFound = 0
   repeat
      i = i + 1
      local spellInfo = parseSpellInfo(i)
      if spellInfo then
         table.insert(spells, spellInfo)
      else
         notFound = notFound + 1
      end
   until notFound > 500000
   return spells
end

local function findSelectionIndexByIconId(iconId)
	for i = 1, #dataProviderTable do
		if iconId == dataProviderTable[i].icon then
			return i
		end
	end
end

local function findSelectionIndexBySpellID(spellID)
	for i = 1, #dataProviderTable do
		if spellID == dataProviderTable[i].spellID then
			return i
		end
	end
end

local iconSelectorFrameMixin = {}


function iconSelectorFrameMixin:OnShow()
	allSpells = allSpells or fetchallSpells()
	IconSelectorPopupFrameTemplateMixin.OnShow(self);
	self.BorderBox.IconSelectorEditBox:SetFocus();
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN);
	self:RefreshIconDataProvider();
	self.BorderBox.IconSelectorEditBox:OnTextChanged();

	local function OnIconSelected(selectionIndex, iconID)
		self.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(iconID);

		-- Index is not yet set, but we know if an icon in IconSelector was selected it was in the list, so set directly.

		if self.BorderBox.SelectedIconArea.SelectedIconButton.SelectedTexture then
			self.BorderBox.SelectedIconArea.SelectedIconButton.SelectedTexture:SetShown(false);
		end
		self.BorderBox.SelectedIconArea.SelectedIconText.SelectedIconHeader:SetText(ICON_SELECTION_TITLE_CURRENT);
		self.BorderBox.SelectedIconArea.SelectedIconText.SelectedIconDescription:SetText(ICON_SELECTION_CLICK);
	end
    self.IconSelector:SetSelectedCallback(OnIconSelected);
end

function iconSelectorFrameMixin:RefreshIconDataProvider(inputText)
	local view = self.IconSelector.ScrollBox:GetView()

	if inputText and inputText:len() > 0 then
		dataProviderTable = filteredSpells
	else
		dataProviderTable = allSpells
	end
	if deduplicate then
		dataProviderTable = deduplicateIcons(dataProviderTable)
	end

	self.iconDataProvider = CreateIndexRangeDataProvider(#dataProviderTable)
	self:Update()
	--view:SetDataProvider(self.iconDataProvider)
end

function iconSelectorFrameMixin:GetNumIcons()
	return #dataProviderTable
end

function iconSelectorFrameMixin:GetIconByIndex(index)
	return dataProviderTable[index].icon
end

function iconSelectorFrameMixin:Update()
	-- Determine whether we're selecting a new icon or we are changing one
	if selectedIconId then
		local selectionIndex = findSelectionIndexByIconId(selectedIconId)
		if selectionIndex then
			self.IconSelector:SetSelectedIndex(selectionIndex);
			self.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(dataProviderTable[selectionIndex].icon);
		end
	end

	local getSelection = GenerateClosure(self.GetIconByIndex, self);
	local getNumSelections = GenerateClosure(self.GetNumIcons, self);
	self.IconSelector:SetSelectionsDataProvider(getSelection, getNumSelections);
	self.IconSelector:ScrollToSelectedIndex();


	-- if self.BorderBox.SelectedIconArea.SelectedIconButton.SetSelectedTexture then
	-- 	self.BorderBox.SelectedIconArea.SelectedIconButton:SetSelectedTexture();
	-- end

	self:SetSelectedIconText();
end

function iconSelectorFrameMixin:CancelButton_OnClick()
	IconSelectorPopupFrameTemplateMixin.CancelButton_OnClick(self);
end

function iconSelectorFrameMixin:OkayButton_OnClick()
	IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self);

	if onApplyF then
		local selectedIndex = self.IconSelector:GetSelectedIndex()
		onApplyF(dataProviderTable[selectedIndex])
	end
end

local function filterBySpellName(name)
	if type(name) ~= "string" then return end
	if name == "" then return end
 	for i = 1, #allSpells do
		local spell = allSpells[i]
		local found = strfind(spell.name:lower(), name:lower())
		if found then table.insert(filteredSpells, allSpells[i]) end
	end
end


local function filterBySpellId(spellID)
	if type(spellID) ~= "number" then return end
	if spellID <= 0 then return end

	local oneFound = false
 	for i = 1, #allSpells do
		local spell = allSpells[i]
		local spellId = tostring(spell.spellID)
		local found = strfind(spellID, tostring(spellId) or "")
		if found then
			table.insert(filteredSpells, spell)
			oneFound = true
		end
	end
	if not oneFound then --check if this spell really doesnt exist, we might have entered "early" out of fetchallSpells()
		local spellInfo = parseSpellInfo(spellID)
		if spellInfo then
			table.insert(filteredSpells, spellInfo)
		end
	end
end

function iconSelectorFrameMixin:InputChanged(inputFrame)
	wipe(filteredSpells)
	local spellID
	local text
	local inputText =  inputFrame:GetText()
	if inputText then
		--check if its a number / spellID
		local number = tonumber(inputText)
		if number then
			filterBySpellId(number)
		else
			filterBySpellName(inputText)
		end
	end
	self:RefreshIconDataProvider(inputText)
end




function LibSpellIconSelector:Show(iconId, onApply)
	selectedIconId = iconId
	onApplyF = onApply
	if not frame then
		if DoesTemplateExist("IconSelectorPopupFrameTemplate") then
			frame = CreateFrame("frame", nil, UIParent, "IconSelectorPopupFrameTemplate")
			Mixin(frame, iconSelectorFrameMixin)

			if frame.BorderBox.IconTypeDropDown then
				frame.BorderBox.IconTypeDropDown:Hide()
				frame.BorderBox.IconTypeDropDown.Show = function(self) return end
				frame.BorderBox.IconTypeDropDown.SetShown = function(self) return end
			end
		else
			-- use the backported templates and mixins
			--frame = CreateFrame("frame", nil, UIParent, "BackportedIconSelectorPopupFrameTemplate")
			frame = Data.Templates.IconSelectorPopupFrameTemplate(UIParent)
			if frame.OnEvent then
				frame:SetScript("OnEvent", frame.OnEvent)
			end
			Mixin(frame, iconSelectorFrameMixin)
			frame:OnLoad()
		end

		frame:Hide()


		frame.BorderBox.EditBoxHeaderText:SetText("filter by spell id or name")
		frame.BorderBox.DedupCheckbox = CreateFrame("CheckButton", nil, frame.BorderBox, "UICheckButtonTemplate")
		frame.BorderBox.DedupCheckbox:SetSize(25, 25)
		frame.BorderBox.DedupCheckbox:SetPoint("BOTTOMLEFT", 10, 10)
		local text = frame.BorderBox.DedupCheckbox.Text or frame.BorderBox.DedupCheckbox.text
		text:SetText("don't show duplicate icons")
		frame.BorderBox.DedupCheckbox:SetScript("OnClick", function(self)
			deduplicate = self:GetChecked()
			frame:RefreshIconDataProvider()
		end)

		local function IconButtonInitializer(button, selectionIndex, iconID)
			button.OnEnter = function(self)
				local selectionIndex = self:GetSelectionIndex()
				local spell = dataProviderTable[selectionIndex]
				local spellID = spell.spellID
				local spellname = spell.name
				local iconID = spell.icon
				GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
				GameTooltip:AddLine("SpellId: "..tostring(spellID), 1, 1, 1)
				GameTooltip:AddLine("Spell name: "..spellname, 1, 1, 1)
				GameTooltip:AddLine("Icon ID: "..tostring(iconID), 1, 1, 1)
				GameTooltip:Show()
			end

			button.OnLeave = function(self)
				GameTooltip:Hide()
			end

			button:SetScript("OnEnter", button.OnEnter)
			button:SetScript("OnLeave", button.OnLeave)
		end

		hooksecurefunc(frame.IconSelector, "setupCallback", IconButtonInitializer)


		local function inputChanged(editBox)
			frame:InputChanged(editBox)
		end
		frame.BorderBox.OkayButton:Enable()
		frame.BorderBox.IconSelectorEditBox.OnTextChanged = function() end
		frame.BorderBox.IconSelectorEditBox:SetScript("OnTextChanged", inputChanged);
		frame.BorderBox.IconSelectorEditBox:SetScript("OnEnterPressed", inputChanged);
		frame.BorderBox.IconSelectorEditBox:SetScript("OnEscapePressed", function(self) inputChanged(self) self:ClearFocus() end );



		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self)
			  self:StartMoving()
		end)
		frame:SetScript("OnDragStop", function(self)
			  self:StopMovingOrSizing()
		end)
		frame:SetScript("OnShow", frame.OnShow)
		frame:SetScript("OnHide", frame.OnHide)

		frame:ClearAllPoints()
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("FULLSCREEN_DIALOG")
	end
	frame:SetToplevel(true)
	frame.BorderBox.DedupCheckbox:SetChecked(true)
	deduplicate = true
	frame.BorderBox.IconSelectorEditBox:SetText("")
	frame:Show()
	return frame
end