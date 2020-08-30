-- MasterMerchant Main Addon File
-- Last Updated September 15, 2014
-- Written July 2014 by Dan Stone (@khaibit) - dankitymao@gmail.com
-- Extended Feb 2015 - Oct 2016 by (@Philgo68) - Philgo68@gmail.com
-- Released under terms in license accompanying this file.
-- Distribution without license is prohibited!
local LAM = LibAddonMenu2
local LMP = LibMediaProvider

local OriginalGetTradingHouseSearchResultItemInfo
local OriginalGetTradingHouseListingItemInfo
local OriginalSetupPendingPost
local Original_ZO_InventorySlot_OnSlotClicked
g_slotActions = nil

local ITEMS = 'full'
local GUILDS = 'half'
local LISTINGS = 'listings'

CSA_EVENT_SMALL_TEXT = 1
CSA_EVENT_LARGE_TEXT = 2
CSA_EVENT_COMBINED_TEXT = 3
CSA_EVENT_NO_TEXT = 4
CSA_EVENT_RAID_COMPLETE_TEXT = 5
MasterMerchant.oneHour = 3600
MasterMerchant.oneDayInSeconds = 86400
--[[
used to temporarily ignore sales that are so new
the ammount of time in seconds causes the UI to say
the sale was made 1657 months ago or 71582789 minutes ago.
]]--
MasterMerchant.oneYearInSeconds = MasterMerchant.oneDayInSeconds * 365

function MasterMerchant.CenterScreenAnnounce_AddMessage(eventId, category, ...)
    local messageParams = CENTER_SCREEN_ANNOUNCE:CreateMessageParams(category)
    messageParams:ConvertOldParams(...)
    messageParams:SetLifespanMS(3500)
    CENTER_SCREEN_ANNOUNCE:AddMessageWithParams(messageParams)
end

function MasterMerchant:setupGuildColors()
  local nextGuild = 0
  while nextGuild < GetNumGuilds() do
    nextGuild = nextGuild + 1
    local nextGuildID = GetGuildId(nextGuild)
    local nextGuildName = GetGuildName(nextGuildID)
    if nextGuildName ~= "" or nextGuildName ~= nil then
      local r, g, b = GetChatCategoryColor(CHAT_CHANNEL_GUILD_1 - 3 + nextGuild)
      self.guildColor[nextGuildName] = {r, g, b};
    else
      self.guildColor[nextGuildName] = {255, 255, 255};
    end
  end
end

function MasterMerchant:TimeCheck()
    -- setup focus info
    local range = self.savedVariables.defaultDays
    if IsControlKeyDown() and IsShiftKeyDown() then
      range = self.savedVariables.ctrlShiftDays
    elseif IsControlKeyDown() then
      range = self.savedVariables.ctrlDays
    elseif IsShiftKeyDown() then
      range = self.savedVariables.shiftDays
    end

    local daysRange = 10000
    if range == GetString(MM_RANGE_NONE) then return -1, -1 end
    if range == GetString(MM_RANGE_FOCUS1) then daysRange = self.savedVariables.focus1 end
    if range == GetString(MM_RANGE_FOCUS2) then daysRange = self.savedVariables.focus2 end

    return GetTimeStamp() - (86400 * daysRange), daysRange
end

-- Computes the weighted moving average across available data
function MasterMerchant:toolTipStats(itemID, itemIndex, skipDots, goBack, clickable)
  local returnData = {['avgPrice'] = nil, ['numSales'] = nil, ['numDays'] = 10000, ['numItems'] = nil, ['craftCost'] = nil}

  -- make sure we have a list of sales to work with
  if self.salesData[itemID] and self.salesData[itemID][itemIndex] and self.salesData[itemID][itemIndex]['sales'] and #self.salesData[itemID][itemIndex]['sales'] > 0 then

    local list = self.salesData[itemID][itemIndex]['sales']

    local lowerBlacklist = self.savedVariables.blacklist and self.savedVariables.blacklist:lower() or ""

    local timeCheck, daysRange = self:TimeCheck()

    if timeCheck == -1 then return returnData end

    -- setup some initial values
    local initMean = 0
    local initCount = 0
    local oldestTime = nil
    local newestTime = nil
    local lowPrice = nil
    local highPrice = nil
    local daysHistory = 0
     -- IPAIRS
    for i, item in pairs(list) do
      if ((type(i) == 'number' and type(item) == 'table' and type(item.timestamp) == 'number') and item.timestamp > timeCheck) and
        (not zo_plainstrfind(lowerBlacklist, item.buyer:lower())) and
        (not zo_plainstrfind(lowerBlacklist, item.seller:lower())) and
        (not zo_plainstrfind(lowerBlacklist, item.guild:lower())) then
          if oldestTime == nil or oldestTime > item.timestamp then oldestTime = item.timestamp end
          if newestTime == nil or newestTime < item.timestamp then newestTime = item.timestamp end
          initMean = initMean + item.price
          initCount = initCount + item.quant
      end
    end

    if (initCount == 0 and goBack) then
      daysRange = 10000
      timeCheck = GetTimeStamp() - (86400 * daysRange)
      initMean = 0
      initCount = 0
      oldestTime = nil
      newestTime = nil
      lowPrice = nil
      highPrice = nil
      daysHistory = 0
      -- IPAIRS
      for i, item in pairs(list) do
        if (type(i) == 'number' and type(item) == 'table' and type(item.timestamp) == 'number') and
          (not zo_plainstrfind(lowerBlacklist, item.buyer:lower())) and
          (not zo_plainstrfind(lowerBlacklist, item.seller:lower())) and
          (not zo_plainstrfind(lowerBlacklist, item.guild:lower())) then
            if oldestTime == nil or oldestTime > item.timestamp then oldestTime = item.timestamp end
            if newestTime == nil or newestTime < item.timestamp then newestTime = item.timestamp end
            initMean = initMean + item.price
            initCount = initCount + item.quant
        end
      end
    end

    if initCount == 0 then
      returnData = {['avgPrice'] = nil, ['numSales'] = nil, ['numDays'] = daysRange, ['numItems'] = nil}
      return returnData
    end

    if (daysRange == 10000) then
      daysHistory = math.floor((GetTimeStamp() - oldestTime) / 86400.0) + 1
    else
      daysHistory = daysRange
    end

    initMean = initMean / initCount

    -- calc standard deviation
    local standardDeviation = 0
    local sampleCount = 0
    -- IPAIRS
    for i, item in pairs(list) do
      if ((type(i) == 'number' and type(item) == 'table' and type(item.timestamp) == 'number') and item.timestamp > timeCheck) and
        (not zo_plainstrfind(lowerBlacklist, item.buyer:lower())) and
        (not zo_plainstrfind(lowerBlacklist, item.seller:lower())) and
        (not zo_plainstrfind(lowerBlacklist, item.guild:lower())) then
          sampleCount = sampleCount+item.quant
          standardDeviation = standardDeviation + ((((item.price / item.quant) - initMean) ^ 2) * item.quant)
      end
    end
    standardDeviation = math.sqrt(standardDeviation / sampleCount)

    local timeInterval = newestTime - oldestTime
    local avgPrice = 0
    local countSold = 0
    local weigtedCountSold = 0
    local legitSales = 0
    local salesPoints = {}
    -- If all sales data covers less than a day, we'll just do a plain average, nothing to weight
    if timeInterval < 86400 then
      -- IPAIRS
      for i, item in pairs(list) do
        if ((type(i) == 'number' and type(item) == 'table' and type(item.timestamp) == 'number') and item.timestamp > timeCheck) and
          (not zo_plainstrfind(lowerBlacklist, item.buyer:lower())) and
          (not zo_plainstrfind(lowerBlacklist, item.seller:lower())) and
          (not zo_plainstrfind(lowerBlacklist, item.guild:lower())) and
          ((not self.savedVariables.trimOutliers) or math.abs((item.price/item.quant) - initMean) <= (3 * standardDeviation)) then
          avgPrice = avgPrice + item.price
          countSold = countSold + item.quant
          legitSales = legitSales + 1
          if lowPrice == nil or lowPrice > item.price/item.quant then lowPrice = item.price/item.quant end
          if highPrice == nil or highPrice < item.price/item.quant then highPrice = item.price/item.quant end
          if not skipDots then
            local tooltip = nil
            if clickable then
              local stringPrice = '';
              if self.savedVariables.trimDecimals then
                stringPrice = string.format('%.0f', item.price/item.quant)
              else
                stringPrice = string.format('%.2f', item.price/item.quant)
              end
              stringPrice = self.LocalizedNumber(stringPrice)
              if item.quant == 1 then
                tooltip = zo_strformat(GetString(SK_TIME_DAYS), math.floor((GetTimeStamp() - item.timestamp) / 86400.0)) .. " " ..
                  string.format( GetString(MM_GRAPH_TIP_SINGLE), item.guild, item.seller, zo_strformat('<<t:1>>', GetItemLinkName(item.itemLink)), item.buyer, stringPrice)
              else
                tooltip = zo_strformat(GetString(SK_TIME_DAYS), math.floor((GetTimeStamp() - item.timestamp) / 86400.0)) .. " " ..
                  string.format( GetString(MM_GRAPH_TIP), item.guild, item.seller, zo_strformat('<<t:1>>', GetItemLinkName(item.itemLink)), item.quant, item.buyer, stringPrice)
              end
            end
            table.insert(salesPoints, {item.timestamp, item.price/item.quant, self.guildColor[item.guild], tooltip})
          end
        end
      end
      avgPrice = avgPrice / countSold
      returnData = {['avgPrice'] = avgPrice, ['numSales'] = legitSales, ['numDays']= daysHistory, ['numItems'] = countSold,
                    ['graphInfo'] = {['oldestTime'] = oldestTime, ['low'] = lowPrice, ['high'] = highPrice, ['points'] = salesPoints}}
    -- For a weighted average, the latest data gets a weighting of X, where X is the number of
    -- days the data covers, thus making newest data worth more.
    else
      local dayInterval = math.floor((GetTimeStamp() - oldestTime) / 86400.0) + 1
      -- IPAIRS
      for i, item in pairs(list) do
        if ((type(i) == 'number' and type(item) == 'table' and type(item.timestamp) == 'number') and item.timestamp > timeCheck) and
          (not zo_plainstrfind(lowerBlacklist, item.buyer:lower())) and
          (not zo_plainstrfind(lowerBlacklist, item.seller:lower())) and
          (not zo_plainstrfind(lowerBlacklist, item.guild:lower())) and
          ((not self.savedVariables.trimOutliers) or math.abs((item.price/item.quant) - initMean) <= (3 * standardDeviation)) then
          local weightValue = dayInterval - math.floor((GetTimeStamp() - item.timestamp) / 86400.0)
          avgPrice = avgPrice + (item.price * weightValue)
          countSold = countSold + item.quant
          weigtedCountSold = weigtedCountSold + (item.quant * weightValue)
          legitSales = legitSales + 1
          if lowPrice == nil or lowPrice > item.price/item.quant then lowPrice = item.price/item.quant end
          if highPrice == nil or highPrice < item.price/item.quant then highPrice = item.price/item.quant end
          if not skipDots then
            local tooltip = nil
            if clickable then
              local stringPrice = '';
              if self.savedVariables.trimDecimals then
                stringPrice = string.format('%.0f', item.price/item.quant)
              else
                stringPrice = string.format('%.2f', item.price/item.quant)
              end
              stringPrice = self.LocalizedNumber(stringPrice)
              if item.quant == 1 then
                tooltip = zo_strformat(GetString(SK_TIME_DAYS), math.floor((GetTimeStamp() - item.timestamp) / 86400.0)) .. " " ..
                  string.format( GetString(MM_GRAPH_TIP_SINGLE), item.guild, item.seller, zo_strformat('<<t:1>>', GetItemLinkName(item.itemLink)),  item.buyer, stringPrice)
              else
                tooltip = zo_strformat(GetString(SK_TIME_DAYS), math.floor((GetTimeStamp() - item.timestamp) / 86400.0)) .. " " ..
                  string.format( GetString(MM_GRAPH_TIP), item.guild, item.seller, zo_strformat('<<t:1>>', GetItemLinkName(item.itemLink)), item.quant, item.buyer, stringPrice)
              end
            end
            table.insert(salesPoints, {item.timestamp, item.price/item.quant, self.guildColor[item.guild], tooltip})
          end
        end
      end
      avgPrice = avgPrice / weigtedCountSold
      returnData = {['avgPrice'] = avgPrice, ['numSales'] = legitSales, ['numDays'] = daysHistory, ['numItems'] = countSold,
                    ['graphInfo'] = {['oldestTime'] = oldestTime, ['low'] = lowPrice, ['high'] = highPrice, ['points'] = salesPoints}}
    end
  end
  return returnData
end

function MasterMerchant:itemStats(itemLink, clickable)
  local itemID = GetItemLinkItemId(itemLink)
  local itemIndex = MasterMerchant.makeIndexFromLink(itemLink)
  return MasterMerchant:toolTipStats(itemID, itemIndex, nil, nil, clickable)
end

function MasterMerchant:itemHasSales(itemLink)
  local itemID = GetItemLinkItemId(itemLink)
  local itemIndex = MasterMerchant.makeIndexFromLink(itemLink)
  return self.salesData[itemID] and self.salesData[itemID][itemIndex] and self.salesData[itemID][itemIndex]['sales'] and #self.salesData[itemID][itemIndex]['sales'] > 0
end

function MasterMerchant:itemPriceTip(itemLink, chatText, clickable)

  local tipStats = MasterMerchant:itemStats(itemLink, clickable)
  if tipStats.avgPrice then

    local tipFormat
    if tipStats['numDays'] < 2 then
      tipFormat = GetString(MM_TIP_FORMAT_SINGLE)
    else
      tipFormat = GetString(MM_TIP_FORMAT_MULTI)
    end
    local avePriceString = '';
    if (tipStats['avgPrice'] > 100) and self.savedVariables.trimDecimals then
      avePriceString = string.format('%.0f', tipStats['avgPrice'])
      --tipFormat = string.gsub(tipFormat, '.2f', '.0f')
    else
      avePriceString = string.format('%.2f', tipStats['avgPrice'])
    end
    avePriceString = self.LocalizedNumber(avePriceString)
    tipFormat = string.gsub(tipFormat, '.2f', 's')
    tipFormat = string.gsub(tipFormat, 'M.M.', 'MM')

    if not chatText then tipFormat = tipFormat .. '|t16:16:EsoUI/Art/currency/currency_gold.dds|t' end
    local salesString = zo_strformat(GetString(SK_PRICETIP_SALES), tipStats['numSales'])
    if tipStats['numSales'] ~= tipStats['numItems'] then
      salesString = salesString .. zo_strformat(GetString(MM_PRICETIP_ITEMS), tipStats['numItems'])
    end
    return string.format(tipFormat, salesString, tipStats['numDays'], avePriceString), tipStats['avgPrice'], tipStats['graphInfo']
    --return string.format(tipFormat, zo_strformat(GetString(SK_PRICETIP_SALES), tipStats['numSales']), tipStats['numDays'], tipStats['avgPrice']), tipStats['avgPrice'], tipStats['graphInfo']
  else
    return nil, tipStats['numDays'], nil
  end
end

function  MasterMerchant.GetItemLinkRecipeNumIngredients(itemLink)
    local numIngredients = GetItemLinkRecipeNumIngredients(itemLink)
    if numIngredients > 0 then
        return numIngredients
    end

    -- Clear player crafted flag and switch to H0 and see if this is an item resulting from a fixed recipe.
    local switchItemLink = string.gsub(string.gsub(itemLink, '0:1:0:0:0:0|h','0:0:0:0:0:0|h'), '|H1:', '|H0:')
    if MasterMerchant.recipeData[switchItemLink] then
        return GetItemLinkRecipeNumIngredients(MasterMerchant.recipeData[switchItemLink])
    end


    --switch to MM pricing Item style
    local mmStyleLink = string.match(switchItemLink, '|H.-:item:(.-):')
    if mmStyleLink then
        mmStyleLink = mmStyleLink .. ':' .. MasterMerchant.makeIndexFromLink(switchItemLink)
        if MasterMerchant.virtualRecipe[mmStyleLink] then
          return #MasterMerchant.virtualRecipe[mmStyleLink]
        end
    end

    --[[
    -- See if it's a craftable thingy: potion, armor, weapon
    local itemType, specializedItemType = GetItemLinkItemType('itemLink')


    --]]

    --[[
	local itemType = GetItemLinkItemType(itemLink)
  	local equipType = GetItemLinkEquipType(itemLink)
	local weaponType = GetItemLinkWeaponType(itemLink)
	local armorType = GetItemLinkArmorType(itemLink)
	local trait = GetItemLinkTraitInfo(itemLink)
	local quality = GetItemLinkQuality(itemLink)
	local level = GetItemLinkRequiredLevel(itemLink)


    --]]
    return 0
end


function  MasterMerchant.GetItemLinkRecipeIngredientInfo(itemLink, i)
    local ingLink = GetItemLinkRecipeIngredientItemLink(itemLink, i)
    if ingLink ~= '' then
        local _, _, numRequired = GetItemLinkRecipeIngredientInfo(itemLink, i)
        return ingLink, numRequired
    end

    local switchItemLink = string.gsub(string.gsub(itemLink, '0:1:0:0:0:0|h','0:0:0:0:0:0|h'), '|H1:', '|H0:')
    if MasterMerchant.recipeData[switchItemLink] then
        return MasterMerchant.GetItemLinkRecipeIngredientInfo(MasterMerchant.recipeData[switchItemLink], i)
    end

    local mmStyleLink = string.match(switchItemLink, '|H.-:item:(.-):')
    if mmStyleLink then
        mmStyleLink = mmStyleLink .. ':' .. MasterMerchant.makeIndexFromLink(switchItemLink)
        if MasterMerchant.virtualRecipe[mmStyleLink] then
            return MasterMerchant.virtualRecipe[mmStyleLink][i].item, MasterMerchant.virtualRecipe[mmStyleLink][i].required
        end
    end

    return nil, nil

    --[[
    -- See if it's something for which we've built a recipe
    local itemType, specializedItemType = GetItemLinkItemType('itemLink')

    -- script /d(GetItemLinkRequiredLevel('

    -- Glyph |H1:item:5365:145:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h
    -- /script d(GetItemLinkItemType('|H1:item:5365:145:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h'))
    if itemType == ITEMTYPE_GLYPH_ARMOR or itemType == ITEMTYPE_GLYPH_JEWELRY or itemType == ITEMTYPE_GLYPH_WEAPON then
        if i == 3 then
            -- Aspect : Quality / Color
            return MasterMerchant.AspectRunes[GetItemLinkQuality(itemLink)], 1
        end
        local level = GetItemLinkRequiredLevel(itemLink)
        local cp = GetItemLinkRequiredChampionPoints(itemLink)

        if i == 1 then
            -- Potency : Level & Positive/Negative
        end
        if i == 2 then
            -- Essence : Attibute
        end
    end
    --]]
end

function MasterMerchant:itemCraftPrice(itemLink)

    local itemType = GetItemLinkItemType(itemLink)

    if (itemType == ITEMTYPE_POTION) or (itemType == ITEMTYPE_POISON) then

        -- Potions/Posions aren't done yet
        if true then
          return nil
        end

        if not IsItemLinkCrafted(itemLink) then
          return nil
        end
        local level = GetItemLinkRequiredLevel(itemLink) + GetItemLinkRequiredChampionPoints(itemLink)
        local solvent = (itemType == ITEMTYPE_POTION and MasterMerchant.potionSolvents[level]) or MasterMerchant.poisonSolvents[level]
        local ingLink = string.format('|H1:item:%d:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h', solvent)
        local cost = MasterMerchant.GetItemLinePrice(ingLink)

        --for i = 1, GetMaxTraits() do
        --    local hasTraitAbility, traitAbilityDescription, traitCooldown, traitHasScaling, traitMinLevel, traitMaxLevel, traitIsChampionPoints = GetItemLinkTraitOnUseAbilityInfo(itemLink, i)
        --    if(hasTraitAbility) then
        --    end
        --end
        return cost / 4
    end

    local numIngredients = MasterMerchant.GetItemLinkRecipeNumIngredients(itemLink)
    if ((numIngredients or 0) == 0) then
      -- Try to clean up item link by moving it to level 1
      itemLink = itemLink:gsub(":0", ":1", 1)
      numIngredients = MasterMerchant.GetItemLinkRecipeNumIngredients(itemLink)
    end
    if ((numIngredients or 0) > 0) then
      local cost = 0
      for i = 1, numIngredients do
        local ingLink, numRequired = MasterMerchant.GetItemLinkRecipeIngredientInfo(itemLink, i)
        if ingLink then
          cost = cost + (MasterMerchant.GetItemLinePrice(ingLink) * numRequired)
        end
      end

      local itemType, specializedItemType = GetItemLinkItemType(itemLink)
      -- Food or Drink or Recipe Food/Drink
      if ((itemType == ITEMTYPE_DRINK) or (itemType == ITEMTYPE_FOOD)
          or (itemType == ITEMTYPE_RECIPE and (specializedItemType == SPECIALIZED_ITEMTYPE_RECIPE_PROVISIONING_STANDARD_FOOD or specializedItemType == SPECIALIZED_ITEMTYPE_RECIPE_PROVISIONING_STANDARD_DRINK))) then
          cost = cost / 4
      end
      return cost
	  else
      return nil
    end
end

function MasterMerchant:itemCraftPriceTip(itemLink, chatText)
    local cost = self:itemCraftPrice(itemLink)
    if cost then
      craftTip = "Craft Cost: %s"

      if (cost > 100) and self.savedVariables.trimDecimals then
        craftTipString = string.format('%.0f', cost)
      else
        craftTipString = string.format('%.2f', cost)
      end
      craftTipString = self.LocalizedNumber(craftTipString)

      if not chatText then craftTip = craftTip .. '|t16:16:EsoUI/Art/currency/currency_gold.dds|t' end

      return string.format(craftTip, craftTipString)
    else
      return nil
    end
end

function MasterMerchant.loadRecipesFrom(startNumber, endNumber)
        local checkTime = GetGameTimeMilliseconds()
        local recNumber = startNumber - 1
        local resultLink
        local itemLink
        while true do
            recNumber = recNumber + 1

            itemLink = string.format('|H1:item:%d:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h', recNumber)
            local itemType = GetItemLinkItemType(itemLink)
            if itemType == ITEMTYPE_ENCHANTING_RUNE_ESSENCE then
                table.insert(MasterMerchant.essenceRunes, recNumber)
            elseif itemType == ITEMTYPE_ENCHANTING_RUNE_POTENCY then
                table.insert(MasterMerchant.potencyRunes, recNumber)
            elseif itemType == ITEMTYPE_ENCHANTING_RUNE_ASPECT then
                table.insert(MasterMerchant.aspectRunes, recNumber)
            elseif itemType == ITEMTYPE_POTION_BASE then
                MasterMerchant.potionSolvents[GetItemLinkRequiredLevel(itemLink) + GetItemLinkRequiredChampionPoints(itemLink)] = recNumber
            elseif itemType == ITEMTYPE_POISON_BASE then
                MasterMerchant.poisonSolvents[GetItemLinkRequiredLevel(itemLink) + GetItemLinkRequiredChampionPoints(itemLink)] = recNumber
            elseif itemType == ITEMTYPE_REAGENT then
                --[[
                MasterMerchant.reagents[recNumber] = {}
                for i = 1, GetMaxTraits() do
                    local _, traitName = GetItemLinkReagentTraitInfo(itemLink, i)
                    table.insert(MasterMerchant.reagents[recNumber], traitName)
                    -- If you get an error here, you don't know all the flower/rune traits....
                    MasterMerchant.traits[traitName] = MasterMerchant.traits[traitName] or {}
                    table.insert(MasterMerchant.traits[traitName], recNumber)
                end
                --]]
            elseif itemType == ITEMTYPE_RECIPE then
                resultLink = GetItemLinkRecipeResultItemLink(itemLink)

                if (resultLink ~= "") then
                    MasterMerchant.recipeData[resultLink] = itemLink
                    MasterMerchant.recipeCount = MasterMerchant.recipeCount + 1
                    --DEBUG
                    --d(MasterMerchant.recipeCount .. ') ' .. itemLink .. ' --> ' .. resultLink  .. ' ('  .. recNumber .. ')')
                end
            end

            if (recNumber >= endNumber) then
                MasterMerchant.v(5, '|cFFFF00Recipes Initialized -- Found information on ' .. MasterMerchant.recipeCount .. ' recipes.|r')
                MasterMerchant.systemSavedVariables.recipeData = MasterMerchant.recipeData
                break
            end

            if (GetGameTimeMilliseconds() - checkTime) > 20 then
                local LEQ = LibExecutionQueue:new()
                LEQ:ContinueWith(function () MasterMerchant.loadRecipesFrom(recNumber + 1, endNumber) end, 'Recipe Cont')
                break
            end
        end
end

--[[
 ITEMTYPE_GLYPH_ARMOR
 ITEMTYPE_GLYPH_JEWELRY
 ITEMTYPE_GLYPH_WEAPON

 ITEMTYPE_POISON
 ITEMTYPE_POTION

 ITEMTYPE_ALCHEMY_BASE

 ITEMTYPE_INGREDIENT
 ITEMTYPE_RECIPE

 GetString("SI_ITEMTYPE", ITEMTYPE_FOOD)
 GetString("SI_SPECIALIZEDITEMTYPE", SPECIALIZED_ITEMTYPE_BLACKSMITHING_BOOSTER)

 SPECIALIZED_ITEMTYPE_RECIPE_BLACKSMITHING_DIAGRAM_FURNISHING

 GetItemLinkItemType(itemLink)

 33 - ITEMTYPE_POTION_BASE
 58 - ITEMTYPE_POISON_BASE
 31 - ITEMTYPE_REAGENT

 for i = 1, GetMaxTraits() do
  local known, name = GetItemLinkReagentTraitInfo("|H1:item:77583:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", i)
  d(name)
end


|H1:item:45806:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h
|H1:item:45844:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h
|H1:item:45850:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h

--]]
-- LOAD RECIPES
-- /script MasterMerchant.virtualRecipe = nil; MasterMerchant.recipeData = nil; MasterMerchant.setupRecipeInfo()


function MasterMerchant.setupRecipeInfo()
    if not MasterMerchant.recipeData then
        MasterMerchant.recipeData = {}
        MasterMerchant.recipeCount = 0

        MasterMerchant.essenceRunes = {}
        MasterMerchant.aspectRunes = {}
        MasterMerchant.potencyRunes = {}

        MasterMerchant.virtualRecipe = {}
        MasterMerchant.virtualRecipeCount = 0

        MasterMerchant.reagents = {}
        MasterMerchant.traits = {}
        MasterMerchant.potionSolvents = {}
        MasterMerchant.poisonSolvents = {}

        MasterMerchant.v(5, '|cFFFF00Searching Items|r')
        local LEQ = LibExecutionQueue:new()
        LEQ:Add(function () MasterMerchant.loadRecipesFrom(1, 450000) end, 'Search Items')
        LEQ:Add(function () MasterMerchant.BuildEnchantingRecipes(1,1,0) end, 'Enchanting Recipes')
        LEQ:Start()
    end
end

function MasterMerchant.BuildEnchantingRecipes(potency, essence, aspect)

        local checkTime = GetGameTimeMilliseconds()

        while true do
            aspect = aspect + 1
            if aspect > #MasterMerchant.aspectRunes then
                aspect = 1
                essence = essence + 1
            end
            if essence > #MasterMerchant.essenceRunes then
                essence = 1
                potency = potency + 1
            end
            if potency > #MasterMerchant.potencyRunes then
                d('|cFFFF00Glyphs Initialized -- Created information on ' .. MasterMerchant.virtualRecipeCount .. ' glyphs.|r')
                MasterMerchant.systemSavedVariables.virtualRecipe = MasterMerchant.virtualRecipe
                break
            end

            MasterMerchant.virtualRecipeCount = MasterMerchant.virtualRecipeCount + 1
            -- Make Glyph
            local potencyNum = MasterMerchant.potencyRunes[potency]
            local essenceNum = MasterMerchant.essenceRunes[essence]
            local aspectNum = MasterMerchant.aspectRunes[aspect]

            local glyph = GetEnchantingResultingItemLink(5, potencyNum, 5, essenceNum, 5, aspectNum)
            --d(glyph)
            --d(potencyNum .. '.' .. essenceNum .. '.' .. aspectNum)
            if (glyph ~= '') then
                local mmGlyph = string.match(glyph, '|H.-:item:(.-):') .. ':' .. MasterMerchant.makeIndexFromLink(glyph)

                MasterMerchant.virtualRecipe[mmGlyph] = {
                    [1] = {['item'] = string.format('|H1:item:%d:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h', potencyNum), ['required'] = 1},
                    [2] = {['item'] = string.format('|H1:item:%d:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h', essenceNum), ['required'] = 1},
                    [3] = {['item'] = string.format('|H1:item:%d:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h', aspectNum), ['required'] = 1}
                }
            end

            --DEBUG
            --d(glyph)
            --d(MasterMerchant.virtualRecipe[glyph])

            if (GetGameTimeMilliseconds() - checkTime) > 20 then
                local LEQ = LibExecutionQueue:new()
                LEQ:ContinueWith(function () MasterMerchant.BuildEnchantingRecipes(potency, essence, aspect) end, 'Enchanting Recipes Cont')
                break
            end
        end
end

-- Copyright (c) 2014 Matthew Miller (Mattmillus)
--
-- Permission is hereby granted, free of charge, to any person
-- obtaining a copy of this software and associated documentation
-- files (the "Software"), to deal in the Software without
-- restriction, including without limitation the rights to use,
-- copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following
-- conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.

function MasterMerchant:onItemActionLinkStatsLink(itemLink)
  local tipLine, days = MasterMerchant:itemPriceTip(itemLink, true)
  if not tipLine then
    if days == 10000 then
      tipLine = GetString(MM_TIP_FORMAT_NONE)
    else
      tipLine = string.format(GetString(MM_TIP_FORMAT_NONE_RANGE), days)
    end
  end
  if tipLine then
    tipLine = string.gsub(tipLine, 'M.M.', 'MM')
    local ChatEditControl = CHAT_SYSTEM.textEntry.editControl
    if (not ChatEditControl:HasFocus()) then StartChatInput() end
    local itemText = string.gsub(itemLink, '|H0', '|H1')
    ChatEditControl:InsertText(MasterMerchant.concat(tipLine, GetString(MM_TIP_FOR), itemText))
  end
end

function MasterMerchant:onItemActionLinkCCLink(itemLink)
  local tipLine = MasterMerchant:itemCraftPriceTip(itemLink, true)
  if not tipLine then
    tipLine = "No Crafting Price Available"
  end
  if tipLine then
    local ChatEditControl = CHAT_SYSTEM.textEntry.editControl
    if (not ChatEditControl:HasFocus()) then StartChatInput() end
    local itemText = string.gsub(itemLink, '|H0', '|H1')
    ChatEditControl:InsertText(MasterMerchant.concat(tipLine, GetString(MM_TIP_FOR), itemText))
  end
end

function MasterMerchant:onItemActionPopupInfoLink(itemLink)
  ZO_PopupTooltip_SetLink(itemLink)
end

-- Adjusted Per AssemblerManiac request 2019-2-20
function MasterMerchant.LinkHandler_OnLinkMouseUp(link, button, _, _, linkType, ...)
	if button == MOUSE_BUTTON_INDEX_RIGHT and linkType == ITEM_LINK_TYPE and type(link) == 'string' and	#link > 0 and	link ~= '' then
		zo_callLater(function()
      if MasterMerchant:itemCraftPrice(link) then
        AddMenuItem("Craft Cost to Chat", function() MasterMerchant:onItemActionLinkCCLink(link) end)
      end
      AddMenuItem(GetString(MM_STATS_TO_CHAT), function() MasterMerchant:onItemActionLinkStatsLink(link) end)
      ShowMenu()
    end)
  end
end

function MasterMerchant.myOnTooltipMouseUp(control, button, upInside, linkFunction, scene)
    if upInside and button == MOUSE_BUTTON_INDEX_RIGHT then

        local link = linkFunction()

        if (link ~= "" and string.match(link, '|H.-:item:(.-):')) then
            ClearMenu()

            AddMenuItem("Craft Cost to Chat", function() MasterMerchant:onItemActionLinkCCLink(link) end)
            AddMenuItem(GetString(MM_STATS_TO_CHAT), function() MasterMerchant:onItemActionLinkStatsLink(link) end)
            AddMenuItem(GetString(SI_ITEM_ACTION_LINK_TO_CHAT), function() ZO_LinkHandler_InsertLink(zo_strformat(SI_TOOLTIP_ITEM_NAME, link)) end)

            ShowMenu(scene)
        end
    end
end

function MasterMerchant.myProvisionerOnTooltipMouseUp(control, button, upInside)
    MasterMerchant.myOnTooltipMouseUp(control, button, upInside,
    function ()
        local recipeListIndex, recipeIndex = PROVISIONER:GetSelectedRecipeListIndex(), PROVISIONER:GetSelectedRecipeIndex()
        return ZO_LinkHandler_CreateChatLink(GetRecipeResultItemLink, recipeListIndex, recipeIndex)
    end,
    PROVISIONER
    )
end
PROVISIONER.resultTooltip:SetHandler("OnMouseUp", MasterMerchant.myProvisionerOnTooltipMouseUp)
PROVISIONER.resultTooltip:GetNamedChild("Icon"):SetHandler("OnMouseUp", MasterMerchant.myProvisionerOnTooltipMouseUp)

function MasterMerchant.myAlchemyOnTooltipMouseUp(control, button, upInside)
    MasterMerchant.myOnTooltipMouseUp(control, button, upInside,
    function ()
        return ZO_LinkHandler_CreateChatLink(GetAlchemyResultingItemLink, ALCHEMY:GetAllCraftingBagAndSlots())
    end,
    ALCHEMY
    )
end
ALCHEMY.tooltip:SetHandler("OnMouseUp", MasterMerchant.myAlchemyOnTooltipMouseUp)
ALCHEMY.tooltip:GetNamedChild("Icon"):SetHandler("OnMouseUp", MasterMerchant.myAlchemyOnTooltipMouseUp)


function MasterMerchant.mySmithingOnTooltipMouseUp(control, button, upInside)
    MasterMerchant.myOnTooltipMouseUp(control, button, upInside,
    function ()
        return ZO_LinkHandler_CreateChatLink(GetSmithingPatternResultLink, SMITHING.creationPanel:GetSelectedPatternIndex(), SMITHING.creationPanel:GetSelectedMaterialIndex(),
          SMITHING.creationPanel:GetSelectedMaterialQuantity(), SMITHING.creationPanel:GetSelectedItemStyleId(), SMITHING.creationPanel:GetSelectedTraitIndex())
    end,
    SMITHING.creationPanel
    )
end
SMITHING.creationPanel.resultTooltip:SetHandler("OnMouseUp", MasterMerchant.mySmithingOnTooltipMouseUp)
SMITHING.creationPanel.resultTooltip:GetNamedChild("Icon"):SetHandler("OnMouseUp", MasterMerchant.mySmithingOnTooltipMouseUp)

function MasterMerchant.myEnchantingOnTooltipMouseUp(control, button, upInside)
    MasterMerchant.myOnTooltipMouseUp(control, button, upInside,
    function ()
        return ZO_LinkHandler_CreateChatLink(GetEnchantingResultingItemLink, ENCHANTING:GetAllCraftingBagAndSlots())
    end,
    ENCHANTING
    )
end
ENCHANTING.resultTooltip:SetHandler("OnMouseUp", MasterMerchant.myEnchantingOnTooltipMouseUp)
ENCHANTING.resultTooltip:GetNamedChild("Icon"):SetHandler("OnMouseUp", MasterMerchant.myEnchantingOnTooltipMouseUp)



function MasterMerchant:my_NameHandler_OnLinkMouseUp(player, button, control)
  if (type(player) == 'string' and #player > 0) then
    if (button == 2 and player ~= '') then
      ClearMenu()
      AddMenuItem(GetString(SI_SOCIAL_LIST_SEND_MESSAGE), function() StartChatInput(nil, CHAT_CHANNEL_WHISPER, player) end)
      AddMenuItem(GetString(SI_SOCIAL_MENU_SEND_MAIL), function() MAIL_SEND:ComposeMailTo(player) end)
      ShowMenu(control)
    end
  end
end

function MasterMerchant.PostPendingItem(self)
  if self.pendingItemSlot and self.pendingSaleIsValid then
    local itemLink = GetItemLink(BAG_BACKPACK, self.pendingItemSlot)
    local _, stackCount, _ = GetItemInfo(BAG_BACKPACK, self.pendingItemSlot)
    local settingsToUse = MasterMerchant:ActiveSettings()

    local theIID = GetItemLinkItemId(itemLink)
    local itemIndex = MasterMerchant.makeIndexFromLink(itemLink)

    settingsToUse.pricingData = settingsToUse.pricingData or {}
    settingsToUse.pricingData[theIID] = settingsToUse.pricingData[theIID] or {}
    settingsToUse.pricingData[theIID][itemIndex] = self.invoiceSellPrice.sellPrice / stackCount

    if settingsToUse.displayListingMessage then
      local selectedGuildId = GetSelectedTradingHouseGuildId()
      MasterMerchant.v(2, string.format(MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(MM_LISTING_ALERT)),
        zo_strformat('<<t:1>>', itemLink), stackCount, self.invoiceSellPrice.sellPrice, GetGuildName(selectedGuildId)))
    end
  end
end

-- End Copyright (c) 2014 Matthew Miller (Mattmillus)



MasterMerchant.CustomDealCalc = {
  ['@Causa'] = function(setPrice, salesCount, purchasePrice, stackCount)
    local deal = -1
    local margin = 0
    local profit = -1
    if (setPrice) then
      local unitPrice = purchasePrice / stackCount
      profit =(setPrice - unitPrice) * stackCount
      margin = tonumber(string.format('%.2f',(((setPrice * .92) - unitPrice) / unitPrice) * 100))

      if (margin >= 100) then
        deal = 5
      elseif (margin >= 75) then
        deal = 4
      elseif (margin >= 50) then
        deal = 3
      elseif (margin >= 25) then
        deal = 2
      elseif (margin >= 0) then
        deal = 1
      else
        deal = 0
      end
    else
      -- No sales seen
      deal = -2
      margin = nil
    end
    return deal, margin, profit
  end
}

MasterMerchant.CustomDealCalc['@freakyfreak'] = MasterMerchant.CustomDealCalc['@Causa']


function MasterMerchant:myZO_InventorySlot_ShowContextMenu(inventorySlot)
    local st = ZO_InventorySlot_GetType(inventorySlot)
    link = nil
    if st == SLOT_TYPE_ITEM or st == SLOT_TYPE_EQUIPMENT or st == SLOT_TYPE_BANK_ITEM or st == SLOT_TYPE_GUILD_BANK_ITEM or
       st == SLOT_TYPE_TRADING_HOUSE_POST_ITEM or st == SLOT_TYPE_REPAIR or st == SLOT_TYPE_CRAFTING_COMPONENT or st == SLOT_TYPE_PENDING_CRAFTING_COMPONENT or
       st == SLOT_TYPE_PENDING_CRAFTING_COMPONENT or st == SLOT_TYPE_PENDING_CRAFTING_COMPONENT or st == SLOT_TYPE_CRAFT_BAG_ITEM then
        local bag, index = ZO_Inventory_GetBagAndIndex(inventorySlot)
        link = GetItemLink(bag, index)
    end
    if st == SLOT_TYPE_TRADING_HOUSE_ITEM_RESULT then
        link = GetTradingHouseSearchResultItemLink(ZO_Inventory_GetSlotIndex(inventorySlot))
    end
    if st == SLOT_TYPE_TRADING_HOUSE_ITEM_LISTING then
        link = GetTradingHouseListingItemLink(ZO_Inventory_GetSlotIndex(inventorySlot), linkStyle)
    end
    if (link and string.match(link, '|H.-:item:(.-):')) then
		zo_callLater(function()
            if MasterMerchant:itemCraftPrice(link) then
               AddMenuItem("Craft Cost to Chat", function() self:onItemActionLinkCCLink(link) end, MENU_ADD_OPTION_LABEL)
            end
            AddMenuItem(GetString(MM_POPUP_ITEM_DATA), function() self:onItemActionPopupInfoLink(link) end, MENU_ADD_OPTION_LABEL)
            AddMenuItem(GetString(MM_STATS_TO_CHAT), function() self:onItemActionLinkStatsLink(link) end, MENU_ADD_OPTION_LABEL)
            ShowMenu(self)
        end, 50)
    end
end

-- Calculate some stats based on the player's sales
-- and return them as a table.
function MasterMerchant:SalesStats(statsDays)
  -- Initialize some values as we'll be using accumulation in the loop
  -- SK_STATS_TOTAL is a key for the overall stats as a guild is unlikely
  -- to be named that, except maybe just to mess with me :D
  local itemsSold = {['SK_STATS_TOTAL'] = 0}
  local goldMade = {['SK_STATS_TOTAL'] = 0}
  local largestSingle = {['SK_STATS_TOTAL'] = {0, nil}}
  local oldestTime = 0
  local newestTime = 0
  local overallOldestTime = 0
  local kioskSales = {['SK_STATS_TOTAL'] = 0}

  -- Set up the guild chooser, with the all guilds/overall option first
  --(other guilds will be added below)
  local guildDropdown = ZO_ComboBox_ObjectFromContainer(MasterMerchantStatsGuildChooser)
  guildDropdown:ClearItems()
  local allGuilds = guildDropdown:CreateItemEntry(GetString(SK_STATS_ALL_GUILDS), function() self:UpdateStatsWindow('SK_STATS_TOTAL') end)
  guildDropdown:AddItem(allGuilds)

  -- 86,400 seconds in a day; this will be the epoch time statsDays ago
  -- (roughly, actual time computations are a LOT more complex but meh)
  local statsDaysEpoch = GetTimeStamp() - (86400 * statsDays)

  -- Loop through the player's sales and create the stats as appropriate
  -- (everything or everything with a timestamp after statsDaysEpoch)

  indexes = self.SRIndex[MasterMerchant.PlayerSpecialText]
  if indexes then
    for i = 1, #indexes do
      local itemID = indexes[i][1]
      local itemData = indexes[i][2]
      local itemIndex = indexes[i][3]

      local theItem = self.salesData[itemID][itemData]['sales'][itemIndex]
      if theItem.timestamp > statsDaysEpoch then
        -- Items Sold
        itemsSold['SK_STATS_TOTAL'] = itemsSold['SK_STATS_TOTAL'] + 1
        if itemsSold[theItem.guild] ~= nil then
          itemsSold[theItem.guild] = itemsSold[theItem.guild] + 1
        else
          itemsSold[theItem.guild] = 1
        end

        -- Kiosk sales
        if theItem.wasKiosk then
          kioskSales['SK_STATS_TOTAL'] = kioskSales['SK_STATS_TOTAL'] + 1
          if kioskSales[theItem.guild] ~= nil then
            kioskSales[theItem.guild] = kioskSales[theItem.guild] + 1
          else
            kioskSales[theItem.guild] = 1
          end
        end

        -- Gold made
        goldMade['SK_STATS_TOTAL'] = goldMade['SK_STATS_TOTAL'] + theItem.price
        if goldMade[theItem.guild] ~= nil then
          goldMade[theItem.guild] = goldMade[theItem.guild] + theItem.price
        else
          goldMade[theItem.guild] = theItem.price
        end

        -- Check to see if we need to update the newest or oldest timestamp we've seen
        if oldestTime == 0 or theItem.timestamp < oldestTime then oldestTime = theItem.timestamp end
        if newestTime == 0 or theItem.timestamp > newestTime then newestTime = theItem.timestamp end

        -- Largest single sale
        if theItem.price > largestSingle['SK_STATS_TOTAL'][1] then largestSingle['SK_STATS_TOTAL'] = {theItem.price, theItem.itemLink} end
        if largestSingle[theItem.guild] == nil or theItem.price > largestSingle[theItem.guild][1] then
          largestSingle[theItem.guild] = {theItem.price, theItem.itemLink}
        end
      end
      -- Check to see if we need to update the overall oldest time (used to set slider range)
      if overallOldestTime == 0 or theItem.timestamp < overallOldestTime then overallOldestTime = theItem.timestamp end
    end
  end
  -- Newest timestamp seen minus oldest timestamp seen is the number of seconds between
  -- them; divided by 86,400 it's the number of days (or at least close enough for this)
  local timeWindow = newestTime - oldestTime
  local dayWindow = 1
  if timeWindow > 86400 then dayWindow = math.floor(timeWindow / 86400) + 1 end

  local overallTimeWindow = GetTimeStamp() - overallOldestTime
  local overallDayWindow = 1
  if overallTimeWindow > 86400 then overallDayWindow = math.floor(overallTimeWindow / 86400) + 1 end

  local goldPerDay = {}
  local kioskPercentage = {}
  local showFullPrice = self.savedVariables.showFullPrice

  -- Here we'll tweak stats as needed as well as add guilds to the guild chooser
  for theGuildName, guildItemsSold in pairs(itemsSold) do
    goldPerDay[theGuildName] = math.floor(goldMade[theGuildName] / dayWindow)
    local kioskSalesTemp = 0
    if kioskSales[theGuildName] ~= nil then kioskSalesTemp = kioskSales[theGuildName] end
    if guildItemsSold == 0 then
      kioskPercentage[theGuildName] = 0
    else
      kioskPercentage[theGuildName] = math.floor((kioskSalesTemp / guildItemsSold) * 100)
    end

    if theGuildName ~= 'SK_STATS_TOTAL' then
      local guildEntry = guildDropdown:CreateItemEntry(theGuildName, function() self:UpdateStatsWindow(theGuildName) end)
      guildDropdown:AddItem(guildEntry)
    end

    -- If they have the option set to show prices post-cut, calculate that here
    if not showFullPrice then
      local cutMult = 1 - (GetTradingHouseCutPercentage() / 100)
      goldMade[theGuildName] = math.floor(goldMade[theGuildName] * cutMult + 0.5)
      goldPerDay[theGuildName] = math.floor(goldPerDay[theGuildName] * cutMult + 0.5)
      largestSingle[theGuildName][1] = math.floor(largestSingle[theGuildName][1] * cutMult + 0.5)
    end
  end

  -- Return the statistical data in a convenient table
  return { numSold = itemsSold,
           numDays = dayWindow,
           totalDays = overallDayWindow,
           totalGold = goldMade,
           avgGold = goldPerDay,
           biggestSale = largestSingle,
           kioskPercent = kioskPercentage, }
end

-- LibAddon init code
function MasterMerchant:LibAddonInit()
  local panelData = {
    type = 'panel',
    name = 'Master Merchant',
    displayName = GetString(MM_APP_NAME),
    author = GetString(MM_APP_AUTHOR),
    version = self.version,
    registerForDefaults = true,
    website = "https://www.esoui.com/downloads/fileinfo.php?id=2753",
  }
  LAM:RegisterAddonPanel('MasterMerchantOptions', panelData)

  local settingsToUse = MasterMerchant:ActiveSettings()
  local optionsData = {
    -- Sound and Alert options
    [1] = {
      type = 'submenu',
      name = GetString(SK_ALERT_OPTIONS_NAME),
      tooltip = GetString(SK_ALERT_OPTIONS_TIP),
      controls = {
        -- On-Screen Alerts
        [1] = {
          type = 'checkbox',
          name = GetString(SK_ALERT_ANNOUNCE_NAME),
          tooltip = GetString(SK_ALERT_ANNOUNCE_TIP),
          getFunc = function() return self.savedVariables.showAnnounceAlerts end,
          setFunc = function(value) self.savedVariables.showAnnounceAlerts = value end,
        },
        [2] = {
          type = 'checkbox',
          name = GetString(SK_ALERT_CYRODIIL_NAME),
          tooltip = GetString(SK_ALERT_CYRODIIL_TIP),
          getFunc = function() return self.savedVariables.showCyroAlerts end,
          setFunc = function(value) self.savedVariables.showCyroAlerts = value end,
        },
        -- Chat Alerts
        [3] = {
          type = 'checkbox',
          name = GetString(SK_ALERT_CHAT_NAME),
          tooltip = GetString(SK_ALERT_CHAT_TIP),
          getFunc = function() return self.savedVariables.showChatAlerts end,
          setFunc = function(value) self.savedVariables.showChatAlerts = value end,
        },
        -- Sound to use for alerts
        [4] = {
          type = 'dropdown',
          name = GetString(SK_ALERT_TYPE_NAME),
          tooltip = GetString(SK_ALERT_TYPE_TIP),
          choices = self:SoundKeys(),
          getFunc = function() return self:SearchSounds(self.savedVariables.alertSoundName) end,
          setFunc = function(value)
            self.savedVariables.alertSoundName = self:SearchSoundNames(value)
            PlaySound(self.savedVariables.alertSoundName)
          end,
        },
        -- Whether or not to show multiple alerts for multiple sales
        [5] = {
          type = 'checkbox',
          name = GetString(SK_MULT_ALERT_NAME),
          tooltip = GetString(SK_MULT_ALERT_TIP),
          getFunc = function() return self.savedVariables.showMultiple end,
          setFunc = function(value) self.savedVariables.showMultiple = value end,
        },
        -- Offline sales report
        [6] = {
          type = 'checkbox',
          name = GetString(SK_OFFLINE_SALES_NAME),
          tooltip = GetString(SK_OFFLINE_SALES_TIP),
          getFunc = function() return self.savedVariables.offlineSales end,
          setFunc = function(value) self.savedVariables.offlineSales = value end,
        },
      },
    },
    -- Tip display and calculation options
    [2] = {
      type = 'submenu',
      name = GetString(MM_CALC_OPTIONS_NAME),
      tooltip = GetString(MM_CALC_OPTIONS_TIP),
      controls = {
        -- On-Screen Alerts
        [1] = {
          type = 'slider',
          name = GetString(MM_DAYS_FOCUS_ONE_NAME),
          tooltip = GetString(MM_DAYS_FOCUS_ONE_TIP),
          min = 1,
          max = 90,
          getFunc = function() return self.savedVariables.focus1 end,
          setFunc = function(value) self.savedVariables.focus1 = value end,
        },
        [2] = {
          type = 'slider',
          name = GetString(MM_DAYS_FOCUS_TWO_NAME),
          tooltip = GetString(MM_DAYS_FOCUS_TWO_TIP),
          min = 1,
          max = 90,
          getFunc = function() return self.savedVariables.focus2 end,
          setFunc = function(value) self.savedVariables.focus2 = value end,
        },
        -- default time range
        [3] = {
          type = 'dropdown',
          name = GetString(MM_DEFAULT_TIME_NAME),
          tooltip = GetString(MM_DEFAULT_TIME_TIP),
          choices = {GetString(MM_RANGE_ALL),GetString(MM_RANGE_FOCUS1),GetString(MM_RANGE_FOCUS2),GetString(MM_RANGE_NONE)},
          getFunc = function() return self.savedVariables.defaultDays end,
          setFunc = function(value) self.savedVariables.defaultDays = value end,
        },
        -- shift time range
        [4] = {
          type = 'dropdown',
          name = GetString(MM_SHIFT_TIME_NAME),
          tooltip = GetString(MM_SHIFT_TIME_TIP),
          choices = {GetString(MM_RANGE_ALL),GetString(MM_RANGE_FOCUS1),GetString(MM_RANGE_FOCUS2),GetString(MM_RANGE_NONE)},
          getFunc = function() return self.savedVariables.shiftDays end,
          setFunc = function(value) self.savedVariables.shiftDays = value end,
        },
        -- ctrl time range
        [5] = {
          type = 'dropdown',
          name = GetString(MM_CTRL_TIME_NAME),
          tooltip = GetString(MM_CTRL_TIME_TIP),
          choices = {GetString(MM_RANGE_ALL),GetString(MM_RANGE_FOCUS1),GetString(MM_RANGE_FOCUS2),GetString(MM_RANGE_NONE)},
          getFunc = function() return self.savedVariables.ctrlDays end,
          setFunc = function(value) self.savedVariables.ctrlDays = value end,
        },
        -- ctrl-shift time range
        [6] = {
          type = 'dropdown',
          name = GetString(MM_CTRLSHIFT_TIME_NAME),
          tooltip = GetString(MM_CTRLSHIFT_TIME_TIP),
          choices = {GetString(MM_RANGE_ALL),GetString(MM_RANGE_FOCUS1),GetString(MM_RANGE_FOCUS2),GetString(MM_RANGE_NONE)},
          getFunc = function() return self.savedVariables.ctrlShiftDays end,
          setFunc = function(value) self.savedVariables.ctrlShiftDays = value end,
        },
        [7] = {
          type = 'slider',
          name = GetString(MM_NO_DATA_DEAL_NAME),
          tooltip = GetString(MM_NO_DATA_DEAL_TIP),
          min = 0,
          max = 5,
          getFunc = function() return self.savedVariables.noSalesInfoDeal end,
          setFunc = function(value) self.savedVariables.noSalesInfoDeal = value end,
        },
        -- blacklisted players and guilds
        [8] = {
          type = 'editbox',
          name = GetString(MM_BLACKLIST_NAME),
          tooltip = GetString(MM_BLACKLIST_TIP),
          getFunc = function() return self.savedVariables.blacklist end,
          setFunc = function(value) self.savedVariables.blacklist = value end,
        },
        -- customTimeframe
        [9] = {
          type = 'slider',
          name = GetString(MM_CUSTOM_TIMEFRAME_NAME),
          tooltip = GetString(MM_CUSTOM_TIMEFRAME_TIP),
          min = 1,
          max = 24 * 31,
          getFunc = function() return self.savedVariables.customTimeframe end,
          setFunc = function(value) self.savedVariables.customTimeframe = value
            self.savedVariables.customTimeframeText = self.savedVariables.customTimeframe .. ' ' .. self.savedVariables.customTimeframeType
          end,
        },
        -- shift time range
        [10] = {
          type = 'dropdown',
          name = GetString(MM_CUSTOM_TIMEFRAME_SCALE_NAME),
          tooltip = GetString(MM_CUSTOM_TIMEFRAME_SCALE_TIP),
          choices = {GetString(MM_CUSTOM_TIMEFRAME_HOURS),GetString(MM_CUSTOM_TIMEFRAME_DAYS),GetString(MM_CUSTOM_TIMEFRAME_WEEKS),GetString(MM_CUSTOM_TIMEFRAME_GUILD_WEEKS)},
          getFunc = function() return self.savedVariables.customTimeframeType end,
          setFunc = function(value) self.savedVariables.customTimeframeType = value
            self.savedVariables.customTimeframeText = self.savedVariables.customTimeframe .. ' ' .. self.savedVariables.customTimeframeType
          end,
        },
      },
    },
    -- Open main window with mailbox scenes
    [3] = {
      type = 'checkbox',
      name = GetString(SK_OPEN_MAIL_NAME),
      tooltip = GetString(SK_OPEN_MAIL_TIP),
      getFunc = function() return self.savedVariables.openWithMail end,
      setFunc = function(value)
        self.savedVariables.openWithMail = value
        local theFragment = ((settingsToUse.viewSize == ITEMS) and self.uiFragment) or ((settingsToUse.viewSize == GUILDS) and self.guildUiFragment) or self.listingUiFragment
        if value then
          -- Register for the mail scenes
          MAIL_INBOX_SCENE:AddFragment(theFragment)
          MAIL_SEND_SCENE:AddFragment(theFragment)
        else
          -- Unregister for the mail scenes
          MAIL_INBOX_SCENE:RemoveFragment(theFragment)
          MAIL_SEND_SCENE:RemoveFragment(theFragment)
        end
      end,
    },
    -- Open main window with trading house scene
    [4] = {
      type = 'checkbox',
      name = GetString(SK_OPEN_STORE_NAME),
      tooltip = GetString(SK_OPEN_STORE_TIP),
      getFunc = function() return self.savedVariables.openWithStore end,
      setFunc = function(value)
        self.savedVariables.openWithStore = value
        local theFragment = ((settingsToUse.viewSize == ITEMS) and self.uiFragment) or ((settingsToUse.viewSize == GUILDS) and self.guildUiFragment) or self.listingUiFragment
        if value then
          -- Register for the store scene
          TRADING_HOUSE_SCENE:AddFragment(theFragment)
        else
          -- Unregister for the store scene
          TRADING_HOUSE_SCENE:RemoveFragment(theFragment)
        end
      end,
    },
    -- Show full sale price or post-tax price
    [5] = {
      type = 'checkbox',
      name = GetString(SK_FULL_SALE_NAME),
      tooltip = GetString(SK_FULL_SALE_TIP),
      getFunc = function() return self.savedVariables.showFullPrice end,
      setFunc = function(value)
        self.savedVariables.showFullPrice = value
        MasterMerchant.listIsDirty[ITEMS] = true
        MasterMerchant.listIsDirty[GUILDS] = true
        MasterMerchant.listIsDirty[LISTINGS] = true
      end,
    },
    -- Size of sales history
    [6] = {
      type = 'slider',
      name = GetString(SK_HISTORY_DEPTH_NAME),
      tooltip = GetString(SK_HISTORY_DEPTH_TIP),
      min = 1,
      max = 365,
      getFunc = function() return self.systemSavedVariables.historyDepth end,
      setFunc = function(value) self.systemSavedVariables.historyDepth = value end,
    },
    -- Min Number of Items before Purge
    [7] = {
      type = 'slider',
      name = GetString(MM_MIN_ITEM_COUNT_NAME),
      tooltip = GetString(MM_MIN_ITEM_COUNT_TIP),
      min = 0,
      max = 100,
      getFunc = function() return self.systemSavedVariables.minItemCount end,
      setFunc = function(value) self.systemSavedVariables.minItemCount = value end,
    },
    -- Max number of Items
    [8] = {
      type = 'slider',
      name = GetString(MM_MAX_ITEM_COUNT_NAME),
      tooltip = GetString(MM_MAX_ITEM_COUNT_TIP),
      min = 100,
      max = 10000,
      getFunc = function() return self.systemSavedVariables.maxItemCount end,
      setFunc = function(value) self.systemSavedVariables.maxItemCount = value end,
    },
    -- Whether or not to show the pricing data in tooltips
    [9] = {
      type = 'checkbox',
      name = GetString(SK_SHOW_PRICING_NAME),
      tooltip = GetString(SK_SHOW_PRICING_TIP),
      getFunc = function() return self.savedVariables.showPricing end,
      setFunc = function(value) self.savedVariables.showPricing = value end,
    },
    -- Whether or not to show the pricing graph in tooltips
    [10] = {
      type = 'checkbox',
      name = GetString(SK_SHOW_GRAPH_NAME),
      tooltip = GetString(SK_SHOW_GRAPH_TIP),
      getFunc = function() return self.savedVariables.showGraph end,
      setFunc = function(value) self.savedVariables.showGraph = value end,
    },
  -- Whether or not to show tooltips on the graph points
    [11] = {
      type = 'checkbox',
      name = GetString(MM_GRAPH_INFO_NAME),
      tooltip = GetString(MM_GRAPH_INFO_TIP),
      getFunc = function() return self.savedVariables.displaySalesDetails end,
      setFunc = function(value) self.savedVariables.displaySalesDetails = value end,
    },
    -- Whether or not to show the crafting costs data in tooltips
    [12] = {
      type = 'checkbox',
      name = GetString(SK_SHOW_CRAFT_COST_NAME),
      tooltip = GetString(SK_SHOW_CRAFT_COST_TIP),
      getFunc = function() return self.savedVariables.showCraftCost end,
      setFunc = function(value) self.savedVariables.showCraftCost = value end,
    },
    -- Whether or not to show the quality/level adjustment buttons
    [13] = {
      type = 'checkbox',
      name = GetString(MM_LEVEL_QUALITY_NAME),
      tooltip = GetString(MM_LEVEL_QUALITY_TIP),
      getFunc = function() return self.savedVariables.displayItemAnalysisButtons end,
      setFunc = function(value) self.savedVariables.displayItemAnalysisButtons = value end,
    },

    -- Should we show the stack price calculator?
    [14] = {
      type = 'checkbox',
      name = GetString(SK_CALC_NAME),
      tooltip = GetString(SK_CALC_TIP),
      getFunc = function() return self.savedVariables.showCalc end,
      setFunc = function(value) self.savedVariables.showCalc = value end,
    },
    -- should we trim outliers prices?
    [15] = {
      type = 'checkbox',
      name = GetString(SK_TRIM_OUTLIERS_NAME),
      tooltip = GetString(SK_TRIM_OUTLIERS_TIP),
      getFunc = function() return self.savedVariables.trimOutliers end,
      setFunc = function(value) self.savedVariables.trimOutliers = value end,
    },
    -- should we trim off decimals?
    [16] = {
      type = 'checkbox',
      name = GetString(SK_TRIM_DECIMALS_NAME),
      tooltip = GetString(SK_TRIM_DECIMALS_TIP),
      getFunc = function() return self.savedVariables.trimDecimals end,
      setFunc = function(value) self.savedVariables.trimDecimals = value end,
    },
    -- should we replace inventory values?
    [17] = {
      type = 'checkbox',
      name = GetString(MM_REPLACE_INVENTORY_VALUES_NAME),
      tooltip = GetString(MM_REPLACE_INVENTORY_VALUES_TIP),
      getFunc = function() return self.savedVariables.replaceInventoryValues end,
      setFunc = function(value) self.savedVariables.replaceInventoryValues = value end,
    },
    -- should we display info on guild roster?
    [18] = {
      type = 'checkbox',
      name = GetString(SK_ROSTER_INFO_NAME),
      tooltip = GetString(SK_ROSTER_INFO_TIP),
      getFunc = function() return self.savedVariables.diplayGuildInfo end,
      setFunc = function(value) self.savedVariables.diplayGuildInfo = value end,
    },
    -- should we display profit instead of margin?
    [19] = {
      type = 'checkbox',
      name = GetString(MM_SAUCY_NAME),
      tooltip = GetString(MM_SAUCY_TIP),
      getFunc = function() return self.savedVariables.saucy end,
      setFunc = function(value) self.savedVariables.saucy = value end,
    },
    -- should we display a Min Profit Filter in AGS?
    [20] = {
      type = 'checkbox',
      name = GetString(MM_MIN_PROFIT_FILTER_NAME),
      tooltip = GetString(MM_MIN_PROFIT_FILTER_TIP),
      getFunc = function() return self.savedVariables.minProfitFilter end,
      setFunc = function(value) self.savedVariables.minProfitFilter = value end,
    },
    -- should we auto advance to the next page?
    [21] = {
      type = 'checkbox',
      name = GetString(MM_AUTO_ADVANCE_NAME),
      tooltip = GetString(MM_AUTO_ADVANCE_TIP),
      getFunc = function() return self.savedVariables.autoNext end,
      setFunc = function(value) self.savedVariables.autoNext = value end,
    },
    -- should we display the item listed message?
    [22] = {
      type = 'checkbox',
      name = GetString(MM_DISPLAY_LISTING_MESSAGE_NAME),
      tooltip = GetString(MM_DISPLAY_LISTING_MESSAGE_TIP),
      getFunc = function() return self.savedVariables.displayListingMessage end,
      setFunc = function(value) self.savedVariables.displayListingMessage = value end,
    },
    -- Font to use
    [23] = {
      type = 'dropdown',
      name = GetString(SK_WINDOW_FONT_NAME),
      tooltip = GetString(SK_WINDOW_FONT_TIP),
      choices = LMP:List(LMP.MediaType.FONT),
      getFunc = function() return self.savedVariables.windowFont end,
      setFunc = function(value)
        self.savedVariables.windowFont = value
        self:UpdateFonts()
        if self.savedVariables.viewSize == ITEMS then self.scrollList:RefreshVisible()
        elseif self.savedVariables.viewSize == GUILDS then self.guildScrollList:RefreshVisible()
        else self.listingScrollList:RefreshVisible() end
      end,
    },
    -- Verbose MM Messages
    [24] = {
      type = 'slider',
      name = GetString(MM_VERBOSE_NAME),
      tooltip = GetString(MM_VERBOSE_TIP),
      min = 1,
      max = 7,
      getFunc = function() return self.savedVariables.verbose end,
      setFunc = function(value)
                  self.savedVariables.verbose = value
                  self.savedVariables.verbose = value
                  MasterMerchant.verboseLevel = value
                end,
    },
    -- Make all settings account-wide (or not)
    [25] = {
      type = 'checkbox',
      name = GetString(SK_ACCOUNT_WIDE_NAME),
      tooltip = GetString(SK_ACCOUNT_WIDE_TIP),
      getFunc = function() return self.savedVariables.allSettingsAccount end,
      setFunc = function(value)
        if value then
          self.savedVariables.showChatAlerts = self.savedVariables.showChatAlerts
          self.savedVariables.showChatAlerts = self.savedVariables.showMultiple
          self.savedVariables.openWithMail = self.savedVariables.openWithMail
          self.savedVariables.openWithStore = self.savedVariables.openWithStore
          self.savedVariables.showFullPrice = self.savedVariables.showFullPrice
          self.savedVariables.winLeft = self.savedVariables.winLeft
          self.savedVariables.winTop = self.savedVariables.winTop
          self.savedVariables.guildWinLeft = self.savedVariables.guildWinLeft
          self.savedVariables.guildWinTop = self.savedVariables.guildWinTop
          self.savedVariables.statsWinLeft = self.savedVariables.statsWinLeft
          self.savedVariables.statsWinTop = self.savedVariables.statsWinTop
          self.savedVariables.windowFont = self.savedVariables.windowFont
          self.savedVariables.showCalc = self.savedVariables.showCalc
          self.savedVariables.showPricing = self.savedVariables.showPricing
          self.savedVariables.showCraftCost = self.savedVariables.showCraftCost
          self.savedVariables.showGraph = self.savedVariables.showGraph
          self.savedVariables.scanFreq = self.savedVariables.scanFreq
          self.savedVariables.showAnnounceAlerts = self.savedVariables.showAnnounceAlerts
          self.savedVariables.alertSoundName = self.savedVariables.alertSoundName
          self.savedVariables.showUnitPrice = self.savedVariables.showUnitPrice
          self.savedVariables.viewSize = self.savedVariables.viewSize
          self.savedVariables.offlineSales = self.savedVariables.offlineSales
          self.savedVariables.feedbackWinLeft = self.savedVariables.feedbackWinLeft
          self.savedVariables.feedbackWinTop = self.savedVariables.feedbackWinTop
          self.savedVariables.trimOutliers = self.savedVariables.trimOutliers
          self.savedVariables.trimDecimals = self.savedVariables.trimDecimals
          self.savedVariables.replaceInventoryValues = self.savedVariables.replaceInventoryValues
          self.savedVariables.diplayGuildInfo = self.savedVariables.diplayGuildInfo
          self.savedVariables.focus1 = self.savedVariables.focus1
          self.savedVariables.focus2 = self.savedVariables.focus2
          self.savedVariables.defaultDays = self.savedVariables.defaultDays
          self.savedVariables.shiftDays = self.savedVariables.shiftDays
          self.savedVariables.ctrlDays = self.savedVariables.ctrlDays
          self.savedVariables.ctrlShiftDays = self.savedVariables.ctrlShiftDays
          self.savedVariables.blacklisted = self.savedVariables.blacklisted
          self.savedVariables.saucy = self.savedVariables.saucy
          self.savedVariables.minProfitFilter = self.savedVariables.minProfitFilter
          self.savedVariables.autoNext = self.savedVariables.autoNext
          self.savedVariables.displayListingMessage = self.savedVariables.displayListingMessage
          self.savedVariables.noSalesInfoDeal = self.savedVariables.noSalesInfoDeal
          self.savedVariables.displaySalesDetails = self.savedVariables.displaySalesDetails
          self.savedVariables.displayItemAnalysisButtons = self.savedVariables.displayItemAnalysisButtons
          self.savedVariables.verbose = self.savedVariables.verbose
        else
          self.savedVariables.showChatAlerts = self.savedVariables.showChatAlerts
          self.savedVariables.showChatAlerts = self.savedVariables.showMultiple
          self.savedVariables.openWithMail = self.savedVariables.openWithMail
          self.savedVariables.openWithStore = self.savedVariables.openWithStore
          self.savedVariables.showFullPrice = self.savedVariables.showFullPrice
          self.savedVariables.winLeft = self.savedVariables.winLeft
          self.savedVariables.winTop = self.savedVariables.winTop
          self.savedVariables.guildWinLeft = self.savedVariables.guildWinLeft
          self.savedVariables.guildWinTop = self.savedVariables.guildWinTop
          self.savedVariables.statsWinLeft = self.savedVariables.statsWinLeft
          self.savedVariables.statsWinTop = self.savedVariables.statsWinTop
          self.savedVariables.windowFont = self.savedVariables.windowFont
          self.savedVariables.showPricing = self.savedVariables.showPricing
          self.savedVariables.showCraftCost = self.savedVariables.showCraftCost
          self.savedVariables.showGraph = self.savedVariables.showGraph
          self.savedVariables.showCalc = self.savedVariables.showCalc
          self.savedVariables.scanFreq = self.savedVariables.scanFreq
          self.savedVariables.showAnnounceAlerts = self.savedVariables.showAnnounceAlerts
          self.savedVariables.alertSoundName = self.savedVariables.alertSoundName
          self.savedVariables.showUnitPrice = self.savedVariables.showUnitPrice
          self.savedVariables.viewSize = self.savedVariables.viewSize
          self.savedVariables.offlineSales = self.savedVariables.offlineSales
          self.savedVariables.feedbackWinLeft = self.savedVariables.feedbackWinLeft
          self.savedVariables.feedbackWinTop = self.savedVariables.feedbackWinTop
          self.savedVariables.trimOutliers = self.savedVariables.trimOutliers
          self.savedVariables.trimDecimals = self.savedVariables.trimDecimals
          self.savedVariables.replaceInventoryValues = self.savedVariables.replaceInventoryValues
          self.savedVariables.diplayGuildInfo = self.savedVariables.diplayGuildInfo
          self.savedVariables.focus1 = self.savedVariables.focus1
          self.savedVariables.focus2 = self.savedVariables.focus2
          self.savedVariables.defaultDays = self.savedVariables.defaultDays
          self.savedVariables.shiftDays = self.savedVariables.shiftDays
          self.savedVariables.ctrlDays = self.savedVariables.ctrlDays
          self.savedVariables.ctrlShiftDays = self.savedVariables.ctrlShiftDays
          self.savedVariables.blacklisted = self.savedVariables.blacklisted
          self.savedVariables.saucy = self.savedVariables.saucy
          self.savedVariables.minProfitFilter = self.savedVariables.minProfitFilter
          self.savedVariables.autoNext = self.savedVariables.autoNext
          self.savedVariables.displayListingMessage = self.savedVariables.displayListingMessage
          self.savedVariables.noSalesInfoDeal = self.savedVariables.noSalesInfoDeal
          self.savedVariables.displaySalesDetails = self.savedVariables.displaySalesDetails
          self.savedVariables.displayItemAnalysisButtons = self.savedVariables.displayItemAnalysisButtons
          self.savedVariables.verbose = self.savedVariables.verbose
        end
        self.savedVariables.allSettingsAccount = value
      end,
    },
  }

  -- And make the options panel
  LAM:RegisterOptionControls('MasterMerchantOptions', optionsData)
end



function MasterMerchant:PurgeDups()

  if not self.isScanning then
    self:setScanning(true)

    local start = GetTimeStamp()
    local eventArray = { }
    local count = 0
    local newSales

    --spin thru history and remove dups
    for itemNumber, itemNumberData in pairs(self.salesData) do
      for itemIndex, itemData in pairs(itemNumberData) do
        if itemData['sales'] then
          local dup
          newSales = {}
          for _, checking in pairs(itemData['sales']) do
            dup = false
            if checking.id == nil then
              dup = true
            end
            if eventArray[tonumber(checking.id)] then
              dup = true
            end
            if dup then
              -- Remove it by not putting it in the new list, but keep a count
              count = count + 1
            else
              table.insert(newSales, checking)
              eventArray[tonumber(checking.id)] = true
            end
          end
          itemData['sales'] = newSales
        end
      end
    end
    --MasterMerchant.v(2, MasterMerchant.NonContiguousNonNilCount(eventArray))
    eventArray = {} -- clear array

    MasterMerchant.v(2, 'Dup purge: ' .. GetTimeStamp() - start .. ' seconds to clear ' .. count .. ' duplicates.')
    MasterMerchant.v(5, 'Reindexing Everything.')
    local LEQ = LibExecutionQueue:new()
    if count > 0 then
      --rebuild everything
      self.SRIndex = {}

      self.guildPurchases = nil
      self.guildSales = nil
      self.guildItems = nil
      self.myItems = {}
      LEQ:Add(function () self:InitItemHistory() end, 'InitItemHistory')
      LEQ:Add(function () self:indexHistoryTables() end, 'indexHistoryTables')
    end
    LEQ:Add(function () self:setScanning(false); MasterMerchant.v(5, 'Reindexing Complete.') end, 'LetScanningContinue')
    LEQ:Start()
  end
end

function MasterMerchant:CleanMule(dataset)
  local muleIdCount = 0
  local items = {}
  for iid, id in pairs(dataset) do
    if (id ~= nil) and (type(id) == 'table') then
      items[iid] = id
    else
      muleIdCount = muleIdCount + 1
    end
  end
  return muleIdCount
end

function MasterMerchant.NonContiguousNonNilCount(tableObject)
  local count = 0

  for _, v in pairs(tableObject)
  do
      if v ~= nil then count = count + 1 end
  end

  return count
end

function MasterMerchant:checkForDoubles()

  local dataList = {
    [0] = MM00Data.savedVariables.SalesData,
    [1] = MM01Data.savedVariables.SalesData,
    [2] = MM02Data.savedVariables.SalesData,
    [3] = MM03Data.savedVariables.SalesData,
    [4] = MM04Data.savedVariables.SalesData,
    [5] = MM05Data.savedVariables.SalesData,
    [6] = MM06Data.savedVariables.SalesData,
    [7] = MM07Data.savedVariables.SalesData,
    [8] = MM08Data.savedVariables.SalesData,
    [9] = MM09Data.savedVariables.SalesData,
    [10] = MM10Data.savedVariables.SalesData,
    [11] = MM11Data.savedVariables.SalesData,
    [12] = MM12Data.savedVariables.SalesData,
    [13] = MM13Data.savedVariables.SalesData,
    [14] = MM14Data.savedVariables.SalesData,
    [15] = MM15Data.savedVariables.SalesData
  }

  for i = 0,14,1 do
    for itemid, versionlist in pairs(dataList[i]) do
      for versionid, _ in pairs(versionlist) do
        for j = i+1,15,1 do
          if dataList[j][itemid] and dataList[j][itemid][versionid] then
            MasterMerchant.v(5, itemid .. '/' .. versionid .. ' is in ' .. i .. ' and ' .. j .. '.')
          end
        end
      end
    end
  end
end

function MasterMerchant.CleanTimestamp(salesRecord)
  if (salesRecord == nil) or (salesRecord.timestamp == nil) or (type(salesRecord.timestamp) ~= 'number') then return 0 end
  return salesRecord.timestamp
end

function MasterMerchant:iterateOverSalesData(itemid, versionid, saleid, prefunc, loopfunc, postfunc, extraData)

  extraData.versionCount = (extraData.versionCount or 0)
  extraData.idCount = (extraData.idCount or 0)
  extraData.checkMilliseconds = (extraData.checkMilliseconds or 20)

  if prefunc then
    prefunc(extraData)
  end

  local checkTime = GetGameTimeMilliseconds()
  local versionlist
  if itemid == nil then
    itemid, versionlist = next(self.salesData, itemid)
    extraData.versionRemoved = false
    versionid = nil
  else
    versionlist = self.salesData[itemid]
  end
  while (itemid ~= nil) do
    local versiondata
    if versionid == nil then
      versionid, versiondata = next(versionlist, versionid)
      extraData.saleRemoved = false
      saleid = nil
    else
      versiondata = versionlist[versionid]
    end
    while (versionid ~= nil) do
      if versiondata['sales'] then
        local saledata
        if saleid == nil then
          saleid, saledata = next(versiondata['sales'], saleid)
        else
          saledata = versiondata['sales'][saleid]
        end
        while (saleid ~= nil) do
          local skipTheRest = loopfunc(itemid, versionid, versiondata, saleid, saledata, extraData)
          extraData.saleRemoved = extraData.saleRemoved or (versiondata['sales'][saleid] == nil)
          if skipTheRest then
            saleid = nil
          else
            saleid, saledata = next(versiondata['sales'], saleid)
          end
          -- We've run out of time, wait and continue with next sale
          if saleid and (GetGameTimeMilliseconds() - checkTime) > extraData.checkMilliseconds then
            local LEQ = LibExecutionQueue:new()
            LEQ:ContinueWith(function () self:iterateOverSalesData(itemid, versionid, saleid, nil, loopfunc, postfunc, extraData) end, nil)
            return
          end
        end

        if extraData.saleRemoved then
          local sales = {}
          for sid, sd in pairs(versiondata['sales']) do
            if (sd ~= nil) and (type(sd) == 'table') then
              table.insert(sales, sd)
            end
          end
          versiondata['sales'] = sales
        end
      end

      -- If we just deleted all the sales, clear the bucket out
      if (versionlist[versionid] ~= nil and ((versiondata['sales'] == nil) or (MasterMerchant.NonContiguousNonNilCount(versiondata['sales']) < 1) or (not string.match(tostring(versionid), "^%d+:%d+:%d+:%d+:%d+")))) then
        extraData.versionCount = (extraData.versionCount or 0) + 1
        versionlist[versionid] = nil
        extraData.versionRemoved = true
      end

      -- Go onto the next Version
      versionid, versiondata = next(versionlist, versionid)
      extraData.saleRemoved = false
      saleid = nil
      if versionid and (GetGameTimeMilliseconds() - checkTime) > extraData.checkMilliseconds then
        local LEQ = LibExecutionQueue:new()
        LEQ:ContinueWith(function () self:iterateOverSalesData(itemid, versionid, saleid, nil, loopfunc, postfunc, extraData) end, nil)
        return
      end
    end

    if extraData.versionRemoved then
      local versions = {}
      for vid, vd in pairs(self.salesData[itemid]) do
        if (vd ~= nil) and (type(vd) == 'table') then
          versions[vid] = vd
        end
      end
      self.salesData[itemid] = versions
    end

    if (self.salesData[itemid] ~= nil and ((MasterMerchant.NonContiguousNonNilCount(versionlist) < 1) or (type(itemid) ~= 'number'))) then
      extraData.idCount = (extraData.idCount or 0) + 1
      self.salesData[itemid] = nil
    end

    -- Go on to the next Item
    itemid, versionlist = next(self.salesData, itemid)
    extraData.versionRemoved = false
    versionid = nil
  end

  if postfunc then
    postfunc(extraData)
  end
end

function MasterMerchant:CleanOutBad()

  local prefunc = function(extraData)
    extraData.start = GetTimeStamp()
    extraData.moveCount = 0
    extraData.deleteCount = 0
    extraData.checkMilliseconds = 120

    self:setScanning(true)
  end

  local loopfunc = function(itemid, versionid, versiondata, saleid, saledata, extraData)

    saledata.itemDesc = nil
    saledata.itemAdderText = nil

    if saledata['timestamp'] == nil
      or type(saledata['timestamp']) ~= 'number'
      or saledata['timestamp'] < 0
      or saledata['price'] == nil
      or type(saledata['price']) ~= 'number'
      or saledata['quant'] == nil
      or type(saledata['quant']) ~= 'number'
      or saledata['guild'] == nil
      or saledata['buyer'] == nil
      or type(saledata['buyer']) ~= 'string'
      or string.sub(saledata['buyer'], 1, 1) ~= '@'
      or saledata['seller'] == nil
      or type(saledata['seller']) ~= 'string'
      or string.sub(saledata['seller'], 1, 1) ~= '@'
      or saledata['itemLink'] == nil
      or type(saledata['itemLink']) ~= 'string'
      or saledata['id'] == nil
      -- or type(saledata['id']) ~= 'number'
      or (not string.match(tostring(saledata['itemLink']), '|H.-:item:(.-):')) then
        -- Remove it
        versiondata['sales'][saleid] = nil
        extraData.deleteCount = extraData.deleteCount + 1
        return
    end
    local newid = GetItemLinkItemId(saledata['itemLink'])
    local newversion = MasterMerchant.makeIndexFromLink(saledata['itemLink'])
    if ((newid ~= itemid) or (newversion ~= versionid)) then
      -- Move this records by inserting it another list and keep a count
      local theEvent =
      {
        buyer = saledata.buyer,
        guild = saledata.guild,
        itemName = saledata.itemLink,
        quant = tonumber(saledata.quant),
        saleTime = tonumber(saledata.timestamp),
        salePrice = tonumber(saledata.price),
        seller = saledata.seller,
        kioskSale = saledata.wasKiosk,
        id = tonumber(saledata.id)
      }
      MasterMerchant:addToHistoryTables(theEvent)
      extraData.moveCount = extraData.moveCount + 1
      -- Remove it from it's current location
      versiondata['sales'][saleid] = nil
      extraData.deleteCount = extraData.deleteCount + 1
      return
    end
  end

  local postfunc = function(extraData)

    extraData.muleIdCount = 0
    if extraData.deleteCount > 0 then
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM00Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM01Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM02Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM03Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM04Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM05Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM06Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM07Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM08Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM09Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM10Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM11Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM12Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM13Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM14Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM15Data.savedVariables.SalesData)
    end

    MasterMerchant.v(2, 'Cleaning: ' .. GetTimeStamp() - extraData.start .. ' seconds to clean:')
    MasterMerchant.v(2,  '  ' .. extraData.deleteCount - extraData.moveCount .. ' bad sales records removed')
    MasterMerchant.v(2,  '  ' .. extraData.moveCount .. ' sales records re-indexed')
    MasterMerchant.v(2,  '  ' .. extraData.versionCount .. ' bad item versions')
    MasterMerchant.v(2,  '  ' .. extraData.idCount .. ' bad item IDs')
    MasterMerchant.v(2,  '  ' .. extraData.muleIdCount .. ' bad mule item IDs')

    local LEQ = LibExecutionQueue:new()
    if extraData.deleteCount > 0 then
      MasterMerchant.v(5, 'Reindexing Everything.')
      --rebuild everything
      self.SRIndex = {}

      self.guildPurchases = {}
      self.guildSales = {}
      self.guildItems = {}
      self.myItems = {}
      LEQ:Add(function () self:InitItemHistory() end, 'InitItemHistory')
      LEQ:Add(function () self:indexHistoryTables() end, 'indexHistoryTables')
      LEQ:Add(function () MasterMerchant.v(5, 'Reindexing Complete.') end, 'Done')
    end

    LEQ:Add(function ()
      self:setScanning(false)
    end, '')
    LEQ:Start()

  end

  if not self.isScanning then
    self:iterateOverSalesData(nil, nil, nil, prefunc, loopfunc, postfunc, {} )
  end

end

function MasterMerchant:SlideSales(goback)

  local prefunc = function(extraData)
    extraData.start = GetTimeStamp()
    extraData.moveCount = 0
    extraData.oldName = GetDisplayName()
    extraData.newName = extraData.oldName .. 'Slid'
    if extraData.oldName == '@kindredspiritgr' then extraData.newName = '@kindredthesexybiotch' end

    if goback then extraData.oldName, extraData.newName = extraData.newName, extraData.oldName end

    self:setScanning(true)
  end

  local loopfunc = function(itemid, versionid, versiondata, saleid, saledata, extraData)
    if saledata['seller'] == extraData.oldName then
      saledata['seller'] = extraData.newName
      extraData.moveCount = extraData.moveCount + 1
    end
  end

  local postfunc = function(extraData)

    MasterMerchant.v(2, 'Sliding: ' .. GetTimeStamp() - extraData.start .. ' seconds to slide ' .. extraData.moveCount .. ' sales records to ' .. extraData.newName .. '.')
    self.SRIndex[MasterMerchant.PlayerSpecialText] = {}
    self:setScanning(false)

  end

  if not self.isScanning then
    self:iterateOverSalesData(nil, nil, nil, prefunc, loopfunc, postfunc, {} )
  end

end

function MasterMerchant:SpecialMessage(force)
  if GetDisplayName() == '@sylviermoone' or (GetDisplayName() == '@Philgo68' and force) then
    local daysCount = math.floor(((GetTimeStamp() - (1460980800 + 38 * 86400 + 19 * 3600)) / 86400) * 4) / 4
    if (daysCount > (self.systemSavedVariables.daysPast or 0)) or force then
      self.systemSavedVariables.daysPast = daysCount

      local rem = daysCount - math.floor(daysCount)
      daysCount = math.floor(daysCount)

      if rem == 0 then
        MasterMerchant.CenterScreenAnnounce_AddMessage('MasterMerchantAlert', CSA_EVENT_SMALL_TEXT, "Objective_Complete",
          string.format("Keep it up!!  You've made it %s complete days!!", daysCount))
      end

      if rem == 0.25 then
        MasterMerchant.CenterScreenAnnounce_AddMessage('MasterMerchantAlert', CSA_EVENT_SMALL_TEXT, "Objective_Complete",
          string.format("Working your way through day %s...", daysCount + 1))
      end

      if rem == 0.5 then
        MasterMerchant.CenterScreenAnnounce_AddMessage('MasterMerchantAlert', CSA_EVENT_SMALL_TEXT, "Objective_Complete",
          string.format("Day %s half way done!", daysCount + 1))
      end

      if rem == 0.75 then
        MasterMerchant.CenterScreenAnnounce_AddMessage('MasterMerchantAlert', CSA_EVENT_SMALL_TEXT, "Objective_Complete",
          string.format("Just a little more to go in day %s...", daysCount + 1))
      end

    end
  end
end

function MasterMerchant:ExportLastWeek()
  local export = ZO_SavedVars:NewAccountWide('ShopkeeperSavedVars', 1, "EXPORT", {}, nil)

  local dataSet = MasterMerchant.guildPurchases
  local dataSet = MasterMerchant.guildSales

  local numGuilds = GetNumGuilds()
  local guildNum = self.guildNumber
  if guildNum > numGuilds then
    MasterMerchant.v(1, "Invalid Guild Number.")
    return
  end

    local settingsToUse = MasterMerchant:ActiveSettings()
    local guildID = GetGuildId(guildNum)
    local guildName = GetGuildName(guildID)

    MasterMerchant.v(2, guildName)
    export[guildName] = {}
    local list = export[guildName]

    local numGuildMembers = GetNumGuildMembers(guildID)
    for guildMemberIndex = 1, numGuildMembers do
        local displayName, note, rankIndex, status, secsSinceLogoff = GetGuildMemberInfo(guildID, guildMemberIndex)
        local online = (status ~= PLAYER_STATUS_OFFLINE)
        local rankId = GetGuildRankId(guildID, rankIndex)

        local amountBought = 0
        if MasterMerchant.guildPurchases and
            MasterMerchant.guildPurchases[guildName] and
            MasterMerchant.guildPurchases[guildName].sellers and
            MasterMerchant.guildPurchases[guildName].sellers[displayName] and
            MasterMerchant.guildPurchases[guildName].sellers[displayName].sales then
            amountBought = MasterMerchant.guildPurchases[guildName].sellers[displayName].sales[settingsToUse.rankIndexRoster] or 0
        end

        local amountSold = 0
        if MasterMerchant.guildSales and
            MasterMerchant.guildSales[guildName] and
            MasterMerchant.guildSales[guildName].sellers and
            MasterMerchant.guildSales[guildName].sellers[displayName] and
            MasterMerchant.guildSales[guildName].sellers[displayName].sales then
            amountSold = MasterMerchant.guildSales[guildName].sellers[displayName].sales[settingsToUse.rankIndexRoster] or 0
        end

        -- sample [2] = "@Name&Sales&Purchases&Rank"
        table.insert(list, displayName .. "&"  .. amountSold .. "&"  .. amountBought .. "&" .. rankIndex)
    end

end


function MasterMerchant:ExportSalesData()
  local export = ZO_SavedVars:NewAccountWide('ShopkeeperSavedVars', 1, "SALES", {}, nil)

  local numGuilds = GetNumGuilds()
  local guildNum = self.guildNumber
  local guildID
  local guildName

  if guildNum > numGuilds then
    guildName = 'ALL'
  else
    guildID = GetGuildId(guildNum)
    guildName = GetGuildName(guildID)
  end
  export[guildName] = {}
  local list = export[guildName]

  local epochBack = GetTimeStamp() - (86400 * 10)
  for k, v in pairs(self.salesData) do
    for j, dataList in pairs(v) do
      if dataList['sales'] then
        for _, sale in pairs(dataList['sales']) do
          if sale.timestamp >= epochBack and (guildName == 'ALL' or guildName == sale.guild) then
            local itemDesc = dataList['itemDesc']
            itemDesc = itemDesc:gsub("%^.*$","",1)
            itemDesc = string.gsub(" "..itemDesc, "%s%l", string.upper):sub(2)

            table.insert(list,
              sale.seller .. "&" ..
              sale.buyer .. "&" ..
              sale.itemLink .. "&" ..
              sale.quant .. "&" ..
              sale.timestamp .. "&" ..
              tostring(sale.wasKiosk) .. "&" ..
              sale.price .. "&" ..
              sale.guild .. "&" ..
              itemDesc .. "&" ..
              dataList['itemAdderText']
              )

          end
        end
      end
    end
  end

end

-----------------------------------------------------------------------

-- Called after store scans complete, re-creates indexes if need be,
-- and updates the slider range. Once this is done it updates the
-- displayed table, sending a message to chat if the scan was initiated
-- via the 'refresh' or 'reset' buttons.

function MasterMerchant:PostScanParallel(guildName, doAlert)
  -- If the index is blank (first scan after login or after reset),
  -- build the indexes now that we have a scanned table.
  self:setScanningParallel(false, guildName)
  self.veryFirstScan = false
  if self.SRIndex == {} then MasterMerchant:indexHistoryTables() end
  local settingsToUse = MasterMerchant:ActiveSettings()

  -- If there's anything in the alert queue, handle it.
  if #MasterMerchant.alertQueue[guildName] > 0 then
    -- Play an alert chime once if there are any alerts in the queue
    if settingsToUse.showChatAlerts or settingsToUse.showAnnounceAlerts then
      PlaySound(settingsToUse.alertSoundName)
    end

    local numSold = 0
    local totalGold = 0
    local numAlerts = #MasterMerchant.alertQueue[guildName]
    local lastEvent = {}
    for i = 1, numAlerts do
      local theEvent = table.remove(MasterMerchant.alertQueue[guildName], 1)
      numSold = numSold + 1

      -- Adjust the price if they want the post-cut prices instead
      local dispPrice = theEvent.salePrice
      if not settingsToUse.showFullPrice then
        local cutPrice = dispPrice * (1 - (GetTradingHouseCutPercentage() / 100))
        dispPrice = math.floor(cutPrice + 0.5)
      end
      totalGold = totalGold + dispPrice

      -- Offline sales report
      if self.isFirstScan and settingsToUse.offlineSales then
        local stringPrice = self.LocalizedNumber(dispPrice)
        local textTime = self.TextTimeSince(theEvent.saleTime, true)
        if i == 1 then MasterMerchant.v(1, MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(SK_SALES_REPORT))) end
        MasterMerchant.v(1, zo_strformat('<<t:1>>', theEvent.itemName) .. GetString(MM_APP_TEXT_TIMES) .. theEvent.quant .. ' -- ' .. stringPrice .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t -- ' .. theEvent.guild)
        if i == numAlerts then
          -- Total of offline sales
          MasterMerchant.v(1, string.format(GetString(SK_SALES_ALERT_GROUP), numAlerts, self.LocalizedNumber(totalGold)))
          MasterMerchant.v(1, MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(SK_SALES_REPORT_END)))
       end
      -- Subsequent scans
      else
        -- If they want multiple alerts, we'll alert on each loop iteration
        -- or if there's only one.
        if settingsToUse.showMultiple or numAlerts == 1 then
          -- Insert thousands separators for the price
          local stringPrice = self.LocalizedNumber(dispPrice)

          -- On-screen alert; map index 37 is Cyrodiil
          if settingsToUse.showAnnounceAlerts and
            (settingsToUse.showCyroAlerts or GetCurrentMapZoneIndex ~= 37) then

            -- We'll add a numerical suffix to avoid queueing two identical messages in a row
            -- because the alerts will 'miss' if we do
            local textTime = self.TextTimeSince(theEvent.saleTime, true)
            local alertSuffix = ''
            if lastEvent[1] ~= nil and theEvent.itemName == lastEvent[1].itemName and textTime == lastEvent[2] then
              lastEvent[3] = lastEvent[3] + 1
              alertSuffix = ' (' .. lastEvent[3] .. ')'
            else
              lastEvent[1] = theEvent
              lastEvent[2] = textTime
              lastEvent[3] = 1
            end
            -- German word order differs so argument order also needs to be changed
            -- Also due to plurality differences in German, need to differentiate
            -- single item sold vs. multiple of an item sold.
            if self.locale == 'de' then
              if theEvent.quant > 1 then
                MasterMerchant.CenterScreenAnnounce_AddMessage('MasterMerchantAlert', CSA_EVENT_SMALL_TEXT, SOUNDS.NONE,
                  string.format(GetString(SK_SALES_ALERT_COLOR), theEvent.quant, zo_strformat('<<t:1>>', theEvent.itemName),
                                stringPrice, theEvent.guild, textTime) .. alertSuffix)
              else
                MasterMerchant.CenterScreenAnnounce_AddMessage('MasterMerchantAlert', CSA_EVENT_SMALL_TEXT, SOUNDS.NONE,
                  string.format(GetString(SK_SALES_ALERT_SINGLE_COLOR),zo_strformat('<<t:1>>', theEvent.itemName),
                                stringPrice, theEvent.guild, textTime) .. alertSuffix)
              end
            else
              MasterMerchant.CenterScreenAnnounce_AddMessage('MasterMerchantAlert', CSA_EVENT_SMALL_TEXT, SOUNDS.NONE,
                string.format(GetString(SK_SALES_ALERT_COLOR), zo_strformat('<<t:1>>', theEvent.itemName),
                              theEvent.quant, stringPrice, theEvent.guild, textTime) .. alertSuffix)
            end
          end

          -- Chat alert
          if settingsToUse.showChatAlerts then
            if self.locale == 'de' then
              if theEvent.quant > 1 then
                MasterMerchant.v(1, string.format(MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(SK_SALES_ALERT)),
                                      theEvent.quant, zo_strformat('<<t:1>>', theEvent.itemName), stringPrice, theEvent.guild, self.TextTimeSince(theEvent.saleTime, true)))
              else
                MasterMerchant.v(1, string.format(MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(SK_SALES_ALERT_SINGLE)),
                                      zo_strformat('<<t:1>>', theEvent.itemName), stringPrice, theEvent.guild, self.TextTimeSince(theEvent.saleTime, true)))
              end
            else
              MasterMerchant.v(1, string.format(MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(SK_SALES_ALERT)),
                                    zo_strformat('<<t:1>>', theEvent.itemName), theEvent.quant, stringPrice, theEvent.guild, self.TextTimeSince(theEvent.saleTime, true)))
            end
          end
        end
      end

      -- Otherwise, we'll just alert once with a summary at the end
      if not settingsToUse.showMultiple and numAlerts > 1 then
        -- Insert thousands separators for the price
        local stringPrice = self.LocalizedNumber(totalGold)

        if settingsToUse.showAnnounceAlerts then
          MasterMerchant.CenterScreenAnnounce_AddMessage('MasterMerchantAlert', CSA_EVENT_SMALL_TEXT, settingsToUse.alertSoundName,
            string.format(GetString(SK_SALES_ALERT_GROUP_COLOR), numSold, stringPrice))
        else
          MasterMerchant.v(1, string.format(MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(SK_SALES_ALERT_GROUP)),
                                numSold, stringPrice))
        end
      end
    end
  end

  self:SpecialMessage(false)

  -- Set the stats slider past the max if this is brand new data
  if self.isFirstScan and doAlert then MasterMerchantStatsWindowSlider:SetValue(15) end
  self.isFirstScan = false

  -- We only have to refresh scroll list data if the window is actually visible; methods
  -- to show these windows refresh data before display
  if settingsToUse.viewSize == ITEMS then
    if not MasterMerchantWindow:IsHidden() then
      self.scrollList:RefreshData()
    else
      self.listIsDirty[ITEMS] = true
    end
    self.listIsDirty[GUILDS] = true
    self.listIsDirty[LISTINGS] = true
  elseif settingsToUse.viewSize == GUILDS then
    if not MasterMerchantGuildWindow:IsHidden() then
      self.guildScrollList:RefreshData()
    else
      self.listIsDirty[GUILDS] = true
    end
    self.listIsDirty[ITEMS] = true
    self.listIsDirty[LISTINGS] = true
  else
    if not MasterMerchantListingWindow:IsHidden() then
      self.listingScrollList:RefreshData()
    else
      self.listIsDirty[LISTINGS] = true
    end
    self.listIsDirty[ITEMS] = true
    self.listIsDirty[GUILDS] = true
  end
end

function MasterMerchant:ProcessGuildHistoryResponse(eventCode, guildID, category)
  if not MasterMerchant.isInitialized then return end
  if self.isScanning then return end
  MasterMerchant:setScanning(true)

  local guildName = GetGuildName(guildID)
  local numEvents = GetNumGuildEvents(guildID, GUILD_HISTORY_STORE)
  local thePlayer = string.lower(GetDisplayName())
  local eventsAdded = 0
  --local eventsScaned = 0
  local erroneousEvent = false

  local guildMemberInfo = {}
  -- Index the table with the account names themselves as they're
  -- (hopefully!) unique - search much faster
  -- Only takes a few milliseconds to load up
  for i = 1, GetNumGuildMembers(guildID) do
    local guildMemInfo, _, _, _, secsSinceLogoff = GetGuildMemberInfo(guildID, i)
    guildMemberInfo[string.lower(guildMemInfo)] = true
  end

  --MasterMerchant.dm("Debug", "ProcessGuildHistoryResponse: " .. guildName)
  for i = ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"][guildName], numEvents do
    local theEvent = {}
    theEvent.eventType, theEvent.secsSince, theEvent.seller, theEvent.buyer, theEvent.quant, theEvent.itemName, theEvent.salePrice, _, theEvent.id = GetGuildEventInfo(guildID, GUILD_HISTORY_STORE, i)
    theEvent.guild = guildName
    theEvent.saleTime = GetTimeStamp() - theEvent.secsSince
    if theEvent.secsSince > MasterMerchant.oneYearInSeconds then
      erroneousEvent = true
      break
    end

    if theEvent.eventType == GUILD_EVENT_ITEM_SOLD then

      theEvent.kioskSale = (guildMemberInfo[string.lower(theEvent.buyer)] == nil)

      if theEvent.itemName ~= nil and theEvent.seller ~= nil and theEvent.buyer ~= nil and theEvent.salePrice ~= nil then
        -- Insert the entry into the SalesData table and associated indexes
        -- Don't trust ZOS at all, always check for Dups
        local added = MasterMerchant:addToHistoryTables(theEvent)
        -- (doAlert and (self.savedVariables.showChatAlerts or self.savedVariables.showAnnounceAlerts))
        if added and string.lower(theEvent.seller) == thePlayer then
          --MasterMerchant.dm("Debug", "alertQueue updated")
          table.insert(MasterMerchant.alertQueue[theEvent.guild], theEvent)
        else
          --MasterMerchant.dm("Debug", "dangit false")
        end
        if added then
          eventsAdded = eventsAdded + 1
        end
      end

      if GuildSalesAssistant and GuildSalesAssistant.MasterMerchantEdition then
        GuildSalesAssistant:InsertEvent(theEvent)
      end
    end
  end

  --MasterMerchant.v(3, "eventsScaned: " .. eventsScaned)
  if eventsAdded > 0 then
    --[[Completed
    OLD METHOD: Scanning:ProcessGuildHistoryResponse
    This happesn last after all the DoScanParallel, ProcessSomeParallel
    operations are completed.

    NEW METHOD: PostScanParallel
    ]]--
    MasterMerchant.v(5, 'Event Monitor found ' .. eventsAdded .. ' sales records for ' .. guildName .. '.')
    MasterMerchant:PostScanParallel(guildName, true)
  else
    MasterMerchant.v(5, 'Event Monitor found no new sales for ' .. guildName .. '.')
  end

  if erroneousEvent then
    MasterMerchant.v(6, 'Erroneous timestamp for a sales event detected for ' .. guildName .. '.')
    for i = ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"][guildName], numEvents do
      local theEvent = {}
      theEvent.eventType, theEvent.secsSince, theEvent.seller, theEvent.buyer, theEvent.quant, theEvent.itemName, theEvent.salePrice, _, theEvent.id = GetGuildEventInfo(guildID, GUILD_HISTORY_STORE, i)
      if MasterMerchant:CheckForDuplicate(theEvent) then
      else
        ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"][guildName] = i
        ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"][guildName] = i
        break
      end
    end
  else
    ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"][guildName] = numEvents
    ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"][guildName] = numEvents
    --[[
    OLD METHOD: Queue up another scan in 60 seconds if there maybe
    some more left. One minute because the server will sometimes
    transmit events very quickly and without tracking the last
    request we would spam the server.
    if DoesGuildHistoryCategoryHaveMoreEvents(guildID, GUILD_HISTORY_STORE) then
      if GetDiffBetweenTimeStamps(GetTimeStamp(), MasterMerchant.lastHistoryRequest[guildID]) > 60000 then
        MasterMerchant.lastHistoryRequest[guildID] = GetTimeStamp()
        zo_callLater(function() RequestMoreGuildHistoryCategoryEvents(guildID, GUILD_HISTORY_STORE) end, 60000)
      end
    end
    ]]--
  end

  MasterMerchant:setScanning(false)
end

-- Scans all stores a player has access to in parallel.
function MasterMerchant:ScanStoresParallel(doAlert)

  if IsUnitInCombat("player") then
    -- We'll just pick it up on the next call.
    MasterMerchant.v(5, 'In Combat...')
    return
  end

  local guildNum = GetNumGuilds()
  -- Nothing to scan!
  if guildNum == 0 then return end

  --[[
  Order of events:

  Pre Setup: ReIndexSales, ReferenceSales

  Setup: LibAddonInit, SalesStats, initGMTools, initPurchaseTracking,
  TruncateHistory, iterateOverSalesData, InitItemHistory,
  iterateOverSalesData, initRosterStats, InitRosterChanges, BuildMasterList,
  iterateOverSalesData, Full Indexing..., InitScrollLists

  Setup 2: iterateOverSalesData is followed by CleanTimestamp when needed. Although
  TruncateHistory is what calls CleanTimestamp, not any other routine.

  Setup 3: initRosterStats will call AddRosterStats

  Scanning: ScanStoresParallel

  Queued Scanning: ScanOlderParallel, DoScanParallel,
  ProcessSomeParallel, DoScanParallel, ProcessSomeParallel,
  DoScanParallel, ProcessSomeParallel, Added X sales

  Cleanup: PostScanParallel, SalesStats

  Also I have seen PostScanParallel followed by SwitchPrice
  ]]--

  -- If it's been less than 15 seconds since we last scanned the store,
  -- don't do it again so we don't hammer the server either accidentally
  -- or on purpose
  local timeLimit = GetTimeStamp() - 15
  --[[
  Not sure this is accurate, self.requestTimestamp is set
  when using /mm missing and just below and Scan Stores Parallel
  is called to start the entire process.
  ]]--
  MasterMerchant.v(2, 'Event Monitor Activated, watching for guild history updates...')
  self.requestTimestamp = GetTimeStamp()
  self.addedEvents = self.addedEvents or {}

  -- Scan 3 days back to start on a guild
  local newGuildTime = GetTimeStamp() - (24 * 3 * 3600)

  for i = 1, guildNum do
    local guildID = GetGuildId(i)
    local guildName = GetGuildName(guildID)
    self.addedEvents[guildName] = 0
    MasterMerchant.alertQueue[guildName] = {}
    self.lastUpdateTime[guildName] = 0
    self.lastUpdateCount[guildName] = 0
    self.systemSavedVariables.newestItem[guildName] = self.systemSavedVariables.newestItem[guildName] or newGuildTime
    self.systemSavedVariables.lastScan[guildName] = self.systemSavedVariables.lastScan[guildName] or newGuildTime
  end
end


-- Handle the refresh button - although there is no background scan so deduct 50
function MasterMerchant:DoRefresh()
  local guildNum = GetNumGuilds()
  for i = 1, guildNum do
    local guildID = GetGuildId(i)
    local guildName = GetGuildName(guildID)
    if ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"][guildName] < 50 then
      ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"][guildName] = 1
    else
      ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"][guildName] = ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"][guildName] - 50
    end
    MasterMerchant.v(5, "Event tracking index for " .. guildName .. " is now (" .. ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"][guildName] .. ").")
    if ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"][guildName] < 50 then
      ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"][guildName] = 1
    else
      ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"][guildName] = ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"][guildName] - 50
    end
  end
  MasterMerchant.v(4, 'All event tracking indexes decremented by 50.')
end

function MasterMerchant:initGMTools()
  -- Stub for GM Tools init
end

function MasterMerchant:initPurchaseTracking()
  -- Stub for Purchase Tracking init
end

function MasterMerchant:initSellingAdvice()
  if MasterMerchant.originalSellingSetupCallback then return end

  if TRADING_HOUSE then

    local dataType = TRADING_HOUSE.postedItemsList.dataTypes[2]

    MasterMerchant.originalSellingSetupCallback = dataType.setupCallback
    if MasterMerchant.originalSellingSetupCallback then
        dataType.setupCallback = function(...)
            local row, data = ...
            MasterMerchant.originalSellingSetupCallback(...)
            zo_callLater(function() MasterMerchant.AddSellingAdvice(row, data) end, 1)
        end
    else
      MasterMerchant.v(5, GetString(MM_ADVICE_ERROR))
    end
  end

  if TRADING_HOUSE_GAMEPAD then
  end
end

function MasterMerchant.AddSellingAdvice(rowControl, result)
  local sellingAdvice = rowControl:GetNamedChild('SellingAdvice')
  if(not sellingAdvice) then
    local controlName = rowControl:GetName() .. 'SellingAdvice'
    sellingAdvice = rowControl:CreateControl(controlName, CT_LABEL)

    local anchorControl = rowControl:GetNamedChild('TimeRemaining')
    local _, point, relTo, relPoint, offsX, offsY = anchorControl:GetAnchor(0)
    anchorControl:ClearAnchors()
    anchorControl:SetAnchor(point, relTo, relPoint, offsX, offsY - 10)

    sellingAdvice:SetAnchor(TOPLEFT, anchorControl, BOTTOMLEFT, 0, 0)
    sellingAdvice:SetFont('/esoui/common/fonts/univers67.otf|14|soft-shadow-thin')
  end

  local itemLink = GetTradingHouseListingItemLink(result.slotIndex)
  local dealValue, margin, profit = MasterMerchant.GetDealInfo(itemLink, result.purchasePrice, result.stackCount)
  if dealValue then
    if dealValue > -1 then
      if MasterMerchant:ActiveSettings().saucy then
        sellingAdvice:SetText(string.format('%.0f', profit) .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')
      else
        sellingAdvice:SetText(string.format('%.2f', margin) .. '%')
      end
      local r, g, b = GetInterfaceColor(INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS, dealValue)
      if dealValue == 0 then r = 0.98; g = 0.01; b = 0.01; end
      sellingAdvice:SetColor(r, g, b, 1)
      sellingAdvice:SetHidden(false)
    else
      sellingAdvice:SetHidden(true)
    end
  else
    sellingAdvice:SetHidden(true)
  end
  sellingAdvice = nil
end


function MasterMerchant:initBuyingAdvice()
  if MasterMerchant.originalSetupCallback then return end

  if TRADING_HOUSE then

    local dataType = TRADING_HOUSE.searchResultsList.dataTypes[1]

    MasterMerchant.originalSetupCallback = dataType.setupCallback
    if MasterMerchant.originalSetupCallback then
      dataType.setupCallback = function(...)
        local row, data = ...
        MasterMerchant.originalSetupCallback(...)
        zo_callLater(function() MasterMerchant.AddBuyingAdvice(row, data) end, 1)
      end
    else
      MasterMerchant.v(5, GetString(MM_ADVICE_ERROR))
    end
  end

  if TRADING_HOUSE_GAMEPAD then
  end
end

function MasterMerchant.AddBuyingAdvice(rowControl, result)
    local buyingAdvice = rowControl:GetNamedChild('BuyingAdvice')
		if(not buyingAdvice) then
			local controlName = rowControl:GetName() .. 'BuyingAdvice'
      buyingAdvice = rowControl:CreateControl(controlName, CT_LABEL)

      if (not AwesomeGuildStore) then
        local anchorControl = rowControl:GetNamedChild('SellPricePerUnit')
        local _, point, relTo, relPoint, offsX, offsY = anchorControl:GetAnchor(0)
        anchorControl:ClearAnchors()
        anchorControl:SetAnchor(point, relTo, relPoint, offsX, offsY + 10)
      end

      local anchorControl = rowControl:GetNamedChild('TimeRemaining')
      local _, point, relTo, relPoint, offsX, offsY = anchorControl:GetAnchor(0)
      anchorControl:ClearAnchors()
      anchorControl:SetAnchor(point, relTo, relPoint, offsX, offsY - 10)
			buyingAdvice:SetAnchor(TOPLEFT, anchorControl, BOTTOMLEFT, 0, 0)
			buyingAdvice:SetFont('/esoui/common/fonts/univers67.otf|14|soft-shadow-thin')
	  end

    local index = result.slotIndex
	  if(AwesomeGuildStore) then index = result.itemUniqueId end
    local itemLink = GetTradingHouseSearchResultItemLink(index)
    local dealValue, margin, profit = MasterMerchant.GetDealInfo(itemLink, result.purchasePrice, result.stackCount)
    if dealValue then
      if dealValue > -1 then
        if MasterMerchant:ActiveSettings().saucy then
          buyingAdvice:SetText(string.format('%.0f', profit) .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')
        else
          buyingAdvice:SetText(string.format('%.2f', margin) .. '%')
        end
        local r, g, b = GetInterfaceColor(INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS, dealValue)
        if dealValue == 0 then r = 0.98; g = 0.01; b = 0.01; end
        buyingAdvice:SetColor(r, g, b, 1)
        buyingAdvice:SetHidden(false)
      else
        buyingAdvice:SetHidden(true)
      end
    else
      buyingAdvice:SetHidden(true)
    end
    buyingAdvice = nil
end

function MasterMerchant:initRosterStats()
  if MasterMerchant.originalRosterStatsCallback then return end

  self:InitRosterChanges()

  local dataType = GUILD_ROSTER_KEYBOARD.list.dataTypes[GUILD_MEMBER_DATA]

  MasterMerchant.originalRosterStatsCallback = dataType.setupCallback
  if MasterMerchant.originalRosterStatsCallback then
      dataType.setupCallback = function(...)
          local row, data = ...
          MasterMerchant.originalRosterStatsCallback(...)
          zo_callLater(function() MasterMerchant.AddRosterStats(row, data) end, 25)
      end
  else
    MasterMerchant.v(5, GetString(MM_ADVICE_ERROR))
  end
end

function MasterMerchant:BuildMasterList()
  --[[
  This happens when you go to the guild history for a guild.
  This happens each time you change guilds also. Meaning
  it is refreshed each time.

  BuildMasterList, AddRosterStats
  ]]--
    if not self.masterList then return end

    MasterMerchant.originalRosterBuildMasterList(self)

    local settingsToUse = MasterMerchant:ActiveSettings()

    for i = 1, #self.masterList do
        local data = self.masterList[i]
          local amountBought = 0
          if MasterMerchant.guildPurchases and
             MasterMerchant.guildPurchases[self.guildName] and
             MasterMerchant.guildPurchases[self.guildName].sellers and
             MasterMerchant.guildPurchases[self.guildName].sellers[data.displayName] and
             MasterMerchant.guildPurchases[self.guildName].sellers[data.displayName].sales then
             amountBought = MasterMerchant.guildPurchases[self.guildName].sellers[data.displayName].sales[settingsToUse.rankIndexRoster or 1] or 0
          end
          data.bought = amountBought

          local amountSold = 0
          local saleCount = 0
          local priorWeek = 0
          if MasterMerchant.guildSales and
             MasterMerchant.guildSales[self.guildName] and
             MasterMerchant.guildSales[self.guildName].sellers and
             MasterMerchant.guildSales[self.guildName].sellers[data.displayName] and
             MasterMerchant.guildSales[self.guildName].sellers[data.displayName].sales then
             amountSold = MasterMerchant.guildSales[self.guildName].sellers[data.displayName].sales[settingsToUse.rankIndexRoster or 1] or 0
             saleCount = MasterMerchant.guildSales[self.guildName].sellers[data.displayName].count[settingsToUse.rankIndexRoster or 1] or 0
             priorWeek = MasterMerchant.guildSales[self.guildName].sellers[data.displayName].sales[(settingsToUse.rankIndexRoster or 1) + 1] or 0
          end
          data.sold = amountSold
          data.count = saleCount

          --local perChange = -101
          --if (settingsToUse.rankIndexRoster == 1 or settingsToUse.rankIndexRoster == 3 or settingsToUse.rankIndexRoster == 4) and priorWeek > 0 then
          --   perChange = math.floor(((amountSold - priorWeek)/priorWeek) * 1000 + 0.5)/10
          --end
          --data.perChange = perChange

          data.perChange = math.floor(data.sold * 0.035)
    end
end

--/script ZO_SharedRightBackground:SetWidth(1088)
function MasterMerchant:InitRosterChanges()
  local additionalWidth = 360  -- Remember to up size of MM_ExtraBackground in xml

  GUILD_ROSTER_ENTRY_SORT_KEYS['bought'] = { tiebreaker = 'displayName', isNumeric = true }
  GUILD_ROSTER_ENTRY_SORT_KEYS['sold'] = { tiebreaker = 'displayName', isNumeric = true }
  GUILD_ROSTER_ENTRY_SORT_KEYS['count'] = { tiebreaker = 'displayName', isNumeric = true }
  GUILD_ROSTER_ENTRY_SORT_KEYS['perChange'] = { tiebreaker = 'sold', isNumeric = true }

  local isValid, point, relTo, relPoint, offsetX, offsetY = ZO_GuildSharedInfoBank:GetAnchor()
  ZO_GuildSharedInfoBank:SetAnchor(point, nil, relPoint, 240, 40)

  local isValid, point, relTo, relPoint, offsetX, offsetY = ZO_GuildRosterHideOffline:GetAnchor()
  ZO_GuildRosterHideOffline:SetAnchor(point, nil, relPoint, 80, 30)

  MasterMerchant.originalRosterBuildMasterList = ZO_GuildRosterManager.BuildMasterList
  ZO_GuildRosterManager.BuildMasterList = MasterMerchant.BuildMasterList

  local background = CreateControlFromVirtual(ZO_GuildRoster:GetName() .. 'MMBiggerBackground', ZO_GuildRoster, 'MM_ExtraBackground')
  background:SetAnchor(TOPLEFT, ZO_GuildRoster, TOPLEFT, 0, 0)
  background:SetDrawLayer(0)
  background:GetNamedChild('ImageLeft'):SetTextureCoords(0,(additionalWidth + 60)/1024,0,1)
  background:GetNamedChild('ImageLeft'):SetColor(1,1,1,.8)
  background:SetHidden(false)

  headers = ZO_GuildRosterHeaders

  local controlName = headers:GetName() .. 'Bought'
  local boughtHeader = CreateControlFromVirtual(controlName, headers, 'ZO_SortHeader')
  ZO_SortHeader_Initialize(boughtHeader, GetString(SK_PURCHASES_COLUMN), 'bought', ZO_SORT_ORDER_DOWN, TEXT_ALIGN_RIGHT, 'ZoFontGameLargeBold')

  local origWidth = ZO_GuildRoster:GetWidth()
  ZO_GuildRoster:SetWidth(origWidth + additionalWidth)
  local anchorControl = headers:GetNamedChild('Level')
  boughtHeader:SetAnchor(TOPLEFT, anchorControl, TOPRIGHT, 20, 0)
  anchorControl.sortHeaderGroup:AddHeader(boughtHeader)

  boughtHeader:SetDimensions(110,32)
  boughtHeader:SetHidden(false)

  controlName = headers:GetName() .. 'Sold'
  local soldHeader = CreateControlFromVirtual(controlName, headers, 'ZO_SortHeader')
  ZO_SortHeader_Initialize(soldHeader, GetString(SK_SALES_COLUMN), 'sold', ZO_SORT_ORDER_DOWN, TEXT_ALIGN_RIGHT, 'ZoFontGameLargeBold')
  boughtHeader.sortHeaderGroup:AddHeader(soldHeader)
  soldHeader:SetAnchor(LEFT, boughtHeader, RIGHT, 0, 0)
  soldHeader:SetDimensions(110,32)
  soldHeader:SetHidden(false)

  controlName = headers:GetName() .. 'PerChg'
  local percentHeader = CreateControlFromVirtual(controlName, headers, 'ZO_SortHeader')
  ZO_SortHeader_Initialize(percentHeader, GetString(SK_PER_CHANGE_COLUMN), 'perChange', ZO_SORT_ORDER_DOWN, TEXT_ALIGN_RIGHT, 'ZoFontGameLargeBold')
  boughtHeader.sortHeaderGroup:AddHeader(percentHeader)
  percentHeader:SetAnchor(LEFT, soldHeader, RIGHT, 10, 0)
  percentHeader:SetDimensions(70,32)
  percentHeader:SetHidden(false)
  percentHeader.data = {
    tooltipText = GetString(SK_PER_CHANGE_TIP)
  }
  percentHeader:SetMouseEnabled(true)
  percentHeader:SetHandler("OnMouseEnter", ZO_Options_OnMouseEnter)
  percentHeader:SetHandler("OnMouseExit", ZO_Options_OnMouseExit)


  controlName = headers:GetName() .. 'Count'
  local countHeader = CreateControlFromVirtual(controlName, headers, 'ZO_SortHeader')
  ZO_SortHeader_Initialize(countHeader, GetString(SK_COUNT_COLUMN), 'count', ZO_SORT_ORDER_DOWN, TEXT_ALIGN_RIGHT, 'ZoFontGameLargeBold')
  boughtHeader.sortHeaderGroup:AddHeader(countHeader)
  countHeader:SetAnchor(LEFT, percentHeader, RIGHT, 0, 0)
  countHeader:SetDimensions(80,32)
  countHeader:SetHidden(false)

  local settingsToUse = MasterMerchant:ActiveSettings()
   -- Guild Time dropdown choice box
  local MasterMerchantGuildTime = CreateControlFromVirtual('MasterMerchantRosterTimeChooser', ZO_GuildRoster, 'MasterMerchantStatsGuildDropdown')
  MasterMerchantGuildTime:SetDimensions(180,25)
  MasterMerchantGuildTime:SetAnchor(TOPRIGHT, ZO_GuildRoster, BOTTOMRIGHT, -120, -5)
  MasterMerchantGuildTime.m_comboBox:SetSortsItems(false)

  local timeDropdown = ZO_ComboBox_ObjectFromContainer(MasterMerchantRosterTimeChooser)
  timeDropdown:ClearItems()

  settingsToUse.rankIndexRoster = settingsToUse.rankIndexRoster or 1

  local timeEntry = timeDropdown:CreateItemEntry(GetString(MM_INDEX_TODAY), function() self:UpdateRosterWindow(1) end)
  timeDropdown:AddItem(timeEntry)
  if settingsToUse.rankIndexRoster == 1 then timeDropdown:SetSelectedItem(GetString(MM_INDEX_TODAY)) end

  timeEntry = timeDropdown:CreateItemEntry(GetString(MM_INDEX_3DAY), function() self:UpdateRosterWindow(2) end)
  timeDropdown:AddItem(timeEntry)
  if settingsToUse.rankIndexRoster == 2 then timeDropdown:SetSelectedItem(GetString(MM_INDEX_3DAY)) end

  timeEntry = timeDropdown:CreateItemEntry(GetString(MM_INDEX_THISWEEK), function() self:UpdateRosterWindow(3) end)
  timeDropdown:AddItem(timeEntry)
  if settingsToUse.rankIndexRoster == 3 then timeDropdown:SetSelectedItem(GetString(MM_INDEX_THISWEEK)) end

  timeEntry = timeDropdown:CreateItemEntry(GetString(MM_INDEX_LASTWEEK), function() self:UpdateRosterWindow(4) end)
  timeDropdown:AddItem(timeEntry)
  if settingsToUse.rankIndexRoster == 4 then timeDropdown:SetSelectedItem(GetString(MM_INDEX_LASTWEEK)) end

  timeEntry = timeDropdown:CreateItemEntry(GetString(MM_INDEX_PRIORWEEK), function() self:UpdateRosterWindow(5) end)
  timeDropdown:AddItem(timeEntry)
  if settingsToUse.rankIndexRoster == 5 then timeDropdown:SetSelectedItem(GetString(MM_INDEX_PRIORWEEK)) end

  timeEntry = timeDropdown:CreateItemEntry(GetString(MM_INDEX_7DAY), function() self:UpdateRosterWindow(8) end)
  timeDropdown:AddItem(timeEntry)
  if settingsToUse.rankIndexRoster == 8 then timeDropdown:SetSelectedItem(GetString(MM_INDEX_7DAY)) end

  timeEntry = timeDropdown:CreateItemEntry(GetString(MM_INDEX_10DAY), function() self:UpdateRosterWindow(6) end)
  timeDropdown:AddItem(timeEntry)
  if settingsToUse.rankIndexRoster == 6 then timeDropdown:SetSelectedItem(GetString(MM_INDEX_10DAY)) end

  timeEntry = timeDropdown:CreateItemEntry(GetString(MM_INDEX_28DAY), function() self:UpdateRosterWindow(7) end)
  timeDropdown:AddItem(timeEntry)
  if settingsToUse.rankIndexRoster == 7 then timeDropdown:SetSelectedItem(GetString(MM_INDEX_28DAY)) end

  timeEntry = timeDropdown:CreateItemEntry(settingsToUse.customTimeframeText, function() self:UpdateRosterWindow(9) end)
  timeDropdown:AddItem(timeEntry)
  if settingsToUse.rankIndexRoster == 9 then timeDropdown:SetSelectedItem(settingsToUse.customTimeframeText) end

  GUILD_ROSTER_MANAGER:RefreshData()

end

function MasterMerchant.AddRosterStats(rowControl, result)

    if result == nil then return end

    local settingsToUse = MasterMerchant:ActiveSettings()
    local anchorControl
    local bought = rowControl:GetNamedChild('Bought')

		if(not bought) then
			local controlName = rowControl:GetName() .. 'Bought'
			bought = rowControl:CreateControl(controlName, CT_LABEL)
      anchorControl = rowControl:GetNamedChild('Level')
			bought:SetAnchor(LEFT, anchorControl, RIGHT, 0, 0)
			bought:SetFont('ZoFontGame')
      bought:SetWidth(110)
      bought:SetHidden(false)
      bought:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)

      local level = rowControl:GetNamedChild('Level')
      local note = rowControl:GetNamedChild('Note')
      note:ClearAnchors()
      note:SetAnchor(LEFT, level, RIGHT, -18, 0)
	  end

    local sold = rowControl:GetNamedChild('Sold')
		if(not sold) then
			local controlName = rowControl:GetName() .. 'Sold'
			sold = rowControl:CreateControl(controlName, CT_LABEL)
			sold:SetAnchor(LEFT, bought, RIGHT, 0, 0)
			sold:SetFont('ZoFontGame')
      sold:SetWidth(110)
      sold:SetHidden(false)
      sold:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
	  end

    local percent = rowControl:GetNamedChild('Percent')
		if(not percent) then
			local controlName = rowControl:GetName() .. 'Percent'
			percent = rowControl:CreateControl(controlName, CT_LABEL)
			percent:SetAnchor(LEFT, sold, RIGHT, 0, 0)
			percent:SetFont('ZoFontGame')
      percent:SetWidth(80)
      percent:SetHidden(false)
      percent:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
	  end

    local count = rowControl:GetNamedChild('Count')
		if(not count) then
			local controlName = rowControl:GetName() .. 'Count'
			count = rowControl:CreateControl(controlName, CT_LABEL)
			count:SetAnchor(LEFT, percent, RIGHT, 0, 0)
			count:SetFont('ZoFontGame')
      count:SetWidth(65)
      count:SetHidden(false)
      count:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
	  end

    local stringBought = MasterMerchant.LocalizedNumber(result.bought)
    bought:SetText(stringBought .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')

    local stringSold = MasterMerchant.LocalizedNumber(result.sold)
    sold:SetText(stringSold .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')

    --local stringPercent = '---'
    --if result.perChange ~= -101 then
    --   stringPercent = MasterMerchant.LocalizedNumber(result.perChange) .. '%'
    --end
    --percent:SetText(stringPercent)
    local stringPercent = MasterMerchant.LocalizedNumber(math.floor((result.sold or 0) * 0.035))
    percent:SetText(stringPercent .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')

    local stringCount = MasterMerchant.LocalizedNumber(result.count)
    count:SetText(stringCount)
end




-- Handle the reset button - clear out the search and scan tables,
-- and set the time of the last scan to nil, then force a scan.
function MasterMerchant:DoReset()
  self.salesData = {}
  self.SRIndex = {}

  MM00Data.savedVariables.SalesData = {}
  MM01Data.savedVariables.SalesData = {}
  MM02Data.savedVariables.SalesData = {}
  MM03Data.savedVariables.SalesData = {}
  MM04Data.savedVariables.SalesData = {}
  MM05Data.savedVariables.SalesData = {}
  MM06Data.savedVariables.SalesData = {}
  MM07Data.savedVariables.SalesData = {}
  MM08Data.savedVariables.SalesData = {}
  MM09Data.savedVariables.SalesData = {}
  MM10Data.savedVariables.SalesData = {}
  MM11Data.savedVariables.SalesData = {}
  MM12Data.savedVariables.SalesData = {}
  MM13Data.savedVariables.SalesData = {}
  MM14Data.savedVariables.SalesData = {}
  MM15Data.savedVariables.SalesData = {}

  self.guildPurchases = {}
  self.guildSales = {}
  self.guildItems = {}
  self.myItems = {}
  self.systemSavedVariables.lastScan = {}
  if MasterMerchantGuildWindow:IsHidden() then
    MasterMerchant.scrollList:RefreshData()
  else
    MasterMerchant.guildScrollList:RefreshData()
  end
  self:setScanning(false)
  self.numEvents = {}
  self.systemSavedVariables.newestItem = {}
  self.systemSavedVariables.targetTime = {}
  MasterMerchant.v(2, MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(SK_RESET_DONE)))
  MasterMerchant.v(2, MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(SK_REFRESH_START)))
  self.veryFirstScan = true
  -- Scan back 3 days on inital startup
  local checkTime = GetTimeStamp() - (24 * 3 * 3600)
  local guildNum = 1
  while guildNum <= GetNumGuilds() do
    local guildID = GetGuildId(guildNum)
    local guildName = GetGuildName(guildID)
    MasterMerchant.systemSavedVariables.lastScan[guildName] = checkTime
    MasterMerchant.systemSavedVariables.newestItem[guildName] = checkTime
    guildNum = guildNum + 1
  end
  self:ScanStoresParallel(true)
end

function MasterMerchant:AdjustItems(otherData)
  if not (otherData.savedVariables.ItemsConverted or false) then
    local somethingConverted = false
    for k, v in pairs(otherData.savedVariables.SalesData) do
        for j, dataList in pairs(v) do
            for i = 1, #dataList.sales, 1 do
                dataList.sales[i].itemLink = self:UpdateItemLink(dataList.sales[i].itemLink)
                somethingConverted = true
            end
        end
    end
    otherData.savedVariables.ItemsConverted = true
    if somethingConverted then
      EVENT_MANAGER:RegisterForEvent(self.name, EVENT_PLAYER_ACTIVATED, function()
        ReloadUI('ingame')
      end)
      error(otherData.name .. ' converted.  Please /reloadui to convert the next file...')
    end
  end
end

function MasterMerchant:ReferenceSales(otherData)
  otherData.savedVariables.dataLocations = otherData.savedVariables.dataLocations or {}
  otherData.savedVariables.dataLocations[GetWorldName()] = true

  for itemid, versionlist in pairs(otherData.savedVariables.SalesData) do
    if self.salesData[itemid] then
      for versionid, versiondata in pairs(versionlist) do
        if self.salesData[itemid][versionid] then
          if versiondata.sales then
            self.salesData[itemid][versionid].sales = self.salesData[itemid][versionid].sales or {}
            -- IPAIRS
            for saleid, saledata in pairs(versiondata.sales) do
              if (type(saleid) == 'number' and type(saledata) == 'table' and type(saledata.timestamp) == 'number') then
                table.insert(self.salesData[itemid][versionid].sales, saledata)
              end
            end
            local _, first = next(versiondata.sales, nil)
            if first then
              self.salesData[itemid][versionid].itemIcon = GetItemLinkInfo(first.itemLink)
              self.salesData[itemid][versionid].itemAdderText = self.addedSearchToItem(first.itemLink)
              self.salesData[itemid][versionid].itemDesc = GetItemLinkName(first.itemLink)
            end
          end
        else
          self.salesData[itemid][versionid] = versiondata
        end
      end
      otherData.savedVariables.SalesData[itemid] = nil
    else
      self.salesData[itemid] = versionlist
    end
  end
end

function MasterMerchant:ReIndexSales(otherData)
  local needToReindex = false
  local needToAddDescription = false
  for _, v in pairs(otherData.savedVariables.SalesData) do
    if v then
      for j, dataList in pairs(v) do
        local _, count = string.gsub(j, ':', ':')
        needToReindex = (count ~= 4)
        needToAddDescription = (dataList['itemDesc'] == nil)
        break
      end
      break
    end
  end
  if needToReindex then
    local tempSales = otherData.savedVariables.SalesData
    otherData.savedVariables.SalesData = {}

    for k, v in pairs(tempSales) do
      for j, dataList in pairs(v) do
        -- IPAIRS
        for i, item in pairs(dataList['sales']) do
          if (type(i) == 'number' and type(item) == 'table' and type(item.timestamp) == 'number') then
            local itemIndex = self.makeIndexFromLink(item.itemLink)
            if not otherData.savedVariables.SalesData[k] then otherData.savedVariables.SalesData[k] = {} end
            if otherData.savedVariables.SalesData[k][itemIndex] then
              table.insert(otherData.savedVariables.SalesData[k][itemIndex]['sales'], item)
            else
              otherData.savedVariables.SalesData[k][itemIndex] = {
                ['itemIcon'] = dataList.itemIcon,
                ['itemAdderText'] = self.addedSearchToItem(item.itemLink),
                ['sales'] = {item},
                ['itemDesc'] = GetItemLinkName(item.itemLink)
              }
            end
          end
        end
      end
    end
  elseif needToAddDescription then
    -- spin through and split Item Description into a seperate string
    for _, v in pairs(otherData.savedVariables.SalesData) do
      for _, dataList in pairs(v) do
        _, item = next(dataList['sales'], nil)
        dataList['itemAdderText'] = self.addedSearchToItem(item.itemLink)
        dataList['itemDesc'] = GetItemLinkName(item.itemLink)
      end
    end
  elseif (not self.systemSavedVariables.switchedToChampionRanks) and (GetAPIVersion() >= 100015) then
    for _, v in pairs(otherData.savedVariables.SalesData) do
      for _, dataList in pairs(v) do
        _, item = next(dataList['sales'], nil)
        dataList['itemAdderText'] = self.addedSearchToItem(item.itemLink)
      end
    end
  end
  self.systemSavedVariables.switchedToChampionRanks = (GetAPIVersion() >= 100015)
end

function MasterMerchant.SetupPendingPost(self)
	OriginalSetupPendingPost(self)

	if (self.pendingItemSlot) then
		local itemLink = GetItemLink(BAG_BACKPACK, self.pendingItemSlot)
		local _, stackCount, _ = GetItemInfo(BAG_BACKPACK, self.pendingItemSlot)

    local settingsToUse = MasterMerchant:ActiveSettings()

    local theIID = GetItemLinkItemId(itemLink)
    local itemIndex = MasterMerchant.makeIndexFromLink(itemLink)

    if settingsToUse.pricingData and settingsToUse.pricingData[theIID] and settingsToUse.pricingData[theIID][itemIndex] then
			self:SetPendingPostPrice(math.floor(settingsToUse.pricingData[theIID][itemIndex] * stackCount))
		else
      local tipStats = MasterMerchant:itemStats(itemLink)
      if (tipStats.avgPrice) then
        self:SetPendingPostPrice(math.floor(tipStats.avgPrice * stackCount))
      end
		end
	end
end

-- register event monitor
local function OnPlayerDeactivated(eventCode)
  EVENT_MANAGER:UnregisterForEvent(MasterMerchant.name.."_EventMon", EVENT_GUILD_HISTORY_RESPONSE_RECEIVED)
end
EVENT_MANAGER:RegisterForEvent(MasterMerchant.name.."_EventDisable", EVENT_PLAYER_DEACTIVATED, OnPlayerDeactivated)

local function OnPlayerActivated(eventCode)
  EVENT_MANAGER:RegisterForEvent(MasterMerchant.name.."_EventMon", EVENT_GUILD_HISTORY_RESPONSE_RECEIVED, function(...) MasterMerchant:ProcessGuildHistoryResponse(...) end)
end
EVENT_MANAGER:RegisterForEvent(MasterMerchant.name.."_EventEnable", EVENT_PLAYER_ACTIVATED, OnPlayerActivated)

-- SavedVar defaults
local Defaults =  {
  ['showChatAlerts'] = false,
  ['showMultiple'] = true,
  ['openWithMail'] = true,
  ['openWithStore'] = true,
  ['showFullPrice'] = true,
  ['winLeft'] = 30,
  ['winTop'] = 30,
  ['guildWinLeft'] = 30,
  ['guildWinTop'] = 30,
  ['statsWinLeft'] = 720,
  ['statsWinTop'] = 820,
  ['feedbackWinLeft'] = 720,
  ['feedbackWinTop'] = 420,
  ['windowFont'] = 'ProseAntique',
  ['historyDepth'] = 30,
  ['scanFreq'] = 300,
  ['showAnnounceAlerts'] = true,
  ['showCyroAlerts'] = true,
  ['alertSoundName'] = 'Book_Acquired',
  ['showUnitPrice'] = false,
  ['viewSize'] = ITEMS,
  ['offlineSales'] = true,
  ['showPricing'] = true,
  ['showCraftCost'] = true,
  ['showGraph'] = true,
  ['showCalc'] = true,
  ['rankIndex'] = 1,
  ['rankIndexRoster'] = 1,
  ['viewBuyerSeller'] = 'buyer',
  ['viewGuildBuyerSeller'] = 'seller',
  ['trimOutliers'] = false,
  ['trimDecimals'] = false,
  ['replaceInventoryValues'] = false,
  ['delayInit'] = true,
  ['diplayGuildInfo'] = false,
  ['displaySalesDetails'] = false,
  ['displayItemAnalysisButtons'] = false,
  ['noSalesInfoDeal'] = 2,
  ['focus1'] = 10,
  ['focus2'] = 3,
  ['blacklist'] = '',
  ['defaultDays'] = GetString(MM_RANGE_ALL),
  ['shiftDays'] = GetString(MM_RANGE_FOCUS1),
  ['ctrlDays'] = GetString(MM_RANGE_FOCUS2),
  ['ctrlShiftDays'] = GetString(MM_RANGE_NONE),
  ['saucy'] = false,
  ['autoNext'] = false,
  ['displayListingMessage'] = false,
  ['verbose'] = 4,
  ['dataLocations'] = {}
  ['minItemCount'] = 20
  ['maxItemCount'] = 5000
  ["numEvents"] = {},
  ["lastNonDuplicate"] = {},
  ["eventIndex"] = {},
  ["eventCount"] = {},
  ["oldestEvent"] = {},
}

local function ConvertToFlatSavedVariables()
  local min_count = 20
  local max_count = 5000
  local hist_days = 30
  local temp_blacklist = ""
  if ShopkeeperSavedVars.version == 2 then return end
  for default_key, default_data in pairs(ShopkeeperSavedVars["Default"]) do
    if default_key = "min_count" then
      if min_count < default_data.min_count then min_count = default_data.min_count end
    end
    if default_key = "max_count" then
      if max_count < default_data.max_count then max_count = default_data.max_count end
    end
    if default_key = "hist_days" then
      if hist_days < default_data.hist_days then hist_days = default_data.hist_days end
    end
    if default_key = "temp_blacklist" then
      if default_data.temp_blacklist ~= "" then temp_blacklist = default_data.temp_blacklist end
    end
    for account_name_one, account_name_one_data in pairs(default_data) do
      for account_name_two, account_name_two_data in pairs(account_name_one_data) do
        if account_name_two = "min_count" then
          if min_count < account_name_two_data.min_count then min_count = account_name_two_data.min_count end
        end
        if account_name_two = "max_count" then
          if max_count < account_name_two_data.max_count then max_count = account_name_two_data.max_count end
        end
        if account_name_two = "hist_days" then
          if hist_days < account_name_two_data.hist_days then hist_days = account_name_two_data.hist_days end
        end
        if account_name_two = "temp_blacklist" then
          if account_name_two_data.temp_blacklist ~= "" then temp_blacklist = account_name_two_data.temp_blacklist end
        end
        for account_name_three, account_name_three_data in pairs(account_name_two_data) do
          if account_name_three = "min_count" then
            if min_count < account_name_three_data.min_count then min_count = account_name_three_data.min_count end
          end
          if account_name_three = "max_count" then
            if max_count < account_name_three_data.max_count then max_count = account_name_three_data.max_count end
          end
          if account_name_three = "hist_days" then
            if hist_days < account_name_three_data.hist_days then hist_days = account_name_three_data.hist_days end
          end
          if account_name_three = "temp_blacklist" then
            if account_name_three_data.temp_blacklist ~= "" then temp_blacklist = account_name_three_data.temp_blacklist end
          end
        end
      end
    end
  end
  self.savedVariables = {}
  self.savedVariables.version = 2
  for key, value in pairs(Defaults) do
    ShopkeeperSavedVars[key] = value
  end
  self.savedVariables.historyDepth = hist_days
  self.savedVariables.minItemCount = min_count
  self.savedVariables.maxItemCount = max_count
  self.savedVariables.blacklist = temp_blacklist
  self.savedVariables.dataLocations[GetWorldName()] = true
  self.savedVariables.switchedToChampionRanks = (GetAPIVersion() >= 100015)
end

-- self.acctSavedVariables.delayInit = nil
-- self:ActiveSettings().verbose = value

-- self.systemSavedVariables.verbose = value
-- self.savedVariables.verbose = value
-- Init function
function MasterMerchant:Initialize()

  -- Populate savedVariables
  self.systemSavedVariables = ZO_SavedVars:NewAccountWide('ShopkeeperSavedVars', 1, nil, {}, nil, 'MasterMerchant')
  self.savedVariables = ZO_SavedVars:NewAccountWide('ShopkeeperSavedVars', 1, GetDisplayName(), Defaults)
  
  ConvertToFlatSavedVariables()

  EVENT_MANAGER:RegisterForEvent(MasterMerchant.name.."_Initial", EVENT_PLAYER_ACTIVATED, function(...) MasterMerchant:PlayerLoaded(...) end)

  self.savedVariables.delayInit = nil
  self.savedVariables.newestItem = nil
  self.savedVariables.lastScan = nil

  self.savedVariables.delayInit = nil
  self.savedVariables.newestItem = nil
  self.savedVariables.lastScan = nil

  -- Delay Init Change
  self.systemSavedVariables.delayInit = true

  -- Default in the 'targetTime' settings
  if (self.systemSavedVariables.targetTime == nil) then
    self.systemSavedVariables.targetTime = {}
    for orig_key, orig_value in pairs(self.systemSavedVariables.newestItem) do
      self.systemSavedVariables.targetTime[orig_key] = orig_value
    end
  end

  -- Default in the 'focus' settings
  if (MasterMerchant:ActiveSettings().focus1 == nil) then
      MasterMerchant:ActiveSettings().focus1 = 10
      MasterMerchant:ActiveSettings().focus2 = 3
      MasterMerchant:ActiveSettings().defaultDays = GetString(MM_RANGE_ALL)
      MasterMerchant:ActiveSettings().shiftDays = GetString(MM_RANGE_FOCUS1)
      MasterMerchant:ActiveSettings().ctrlDays = GetString(MM_RANGE_FOCUS2)
      MasterMerchant:ActiveSettings().ctrlShiftDays = GetString(MM_RANGE_NONE)
  end

  if (MasterMerchant:ActiveSettings().customTimeframe == nil or MasterMerchant:ActiveSettings().customTimeframeType == nil) then
    MasterMerchant:ActiveSettings().customTimeframe = 2
    MasterMerchant:ActiveSettings().customTimeframeType = GetString(MM_CUSTOM_TIMEFRAME_GUILD_WEEKS)
  end
  MasterMerchant:ActiveSettings().customTimeframeText = MasterMerchant:ActiveSettings().customTimeframe .. ' ' .. MasterMerchant:ActiveSettings().customTimeframeType

  if (MasterMerchant:ActiveSettings().blacklist == nil) then MasterMerchant:ActiveSettings().blacklist = '' end

  -- Move the historyDepth variable to a system wide area
  if (self.systemSavedVariables.historyDepth == nil) then
    self.systemSavedVariables.historyDepth = MasterMerchant:ActiveSettings().historyDepth or 30;
  end

  -- Default in the Min/Max Item count settings
  if (self.systemSavedVariables.minItemCount == nil) then
      self.systemSavedVariables.minItemCount = 20
      self.systemSavedVariables.maxItemCount = 5000
  end

  -- Default in the replace inventory values setting
  if (MasterMerchant:ActiveSettings().replaceInventoryValues == nil) then
      MasterMerchant:ActiveSettings().replaceInventoryValues = false
  end

  if (MasterMerchant:ActiveSettings().noSalesInfoDeal == nil) then
    MasterMerchant:ActiveSettings().noSalesInfoDeal = 2
  end

  if (MasterMerchant:ActiveSettings().showCraftCost == nil) then
    MasterMerchant:ActiveSettings().showCraftCost = true
  end

  -- Default in the verbose setting
  if (MasterMerchant:ActiveSettings().verbose == nil) then
    MasterMerchant:ActiveSettings().verbose = 4
    MasterMerchant.verboseLevel = 4
  end
  if (type(MasterMerchant:ActiveSettings().verbose) == 'boolean') then
    if MasterMerchant:ActiveSettings().verbose then
      MasterMerchant:ActiveSettings().verbose = 4
      MasterMerchant.verboseLevel = 4
    else
      MasterMerchant:ActiveSettings().verbose = 2
      MasterMerchant.verboseLevel = 2
    end
  end
  MasterMerchant.verboseLevel = MasterMerchant:ActiveSettings().verbose or 4

  -- Move the old single addon sales history to the multi addon sales history
  if self.savedVariables.SalesData then
    local action = {
      [0] = function (k, v) MM00Data.savedVariables.SalesData[k] = v end,
      [1] = function (k, v) MM01Data.savedVariables.SalesData[k] = v end,
      [2] = function (k, v) MM02Data.savedVariables.SalesData[k] = v end,
      [3] = function (k, v) MM03Data.savedVariables.SalesData[k] = v end,
      [4] = function (k, v) MM04Data.savedVariables.SalesData[k] = v end,
      [5] = function (k, v) MM05Data.savedVariables.SalesData[k] = v end,
      [6] = function (k, v) MM06Data.savedVariables.SalesData[k] = v end,
      [7] = function (k, v) MM07Data.savedVariables.SalesData[k] = v end,
      [8] = function (k, v) MM08Data.savedVariables.SalesData[k] = v end,
      [9] = function (k, v) MM09Data.savedVariables.SalesData[k] = v end,
      [10] = function (k, v) MM10Data.savedVariables.SalesData[k] = v end,
      [11] = function (k, v) MM11Data.savedVariables.SalesData[k] = v end,
      [12] = function (k, v) MM12Data.savedVariables.SalesData[k] = v end,
      [13] = function (k, v) MM13Data.savedVariables.SalesData[k] = v end,
      [14] = function (k, v) MM14Data.savedVariables.SalesData[k] = v end,
      [15] = function (k, v) MM15Data.savedVariables.SalesData[k] = v end
    }

    for k, v in pairs(self.savedVariables.SalesData) do
      local hash
      for j, dataList in pairs(v) do
        local item = dataList['sales'][1]
        hash = MasterMerchant.hashString(string.lower(GetItemLinkName(item.itemLink)))
        break
      end
      action[hash](k, v)
    end
    self.savedVariables.SalesData = nil
  end

  -- Covert each data file as needed
  if GetAPIVersion() == 100011 then
    self:AdjustItems(MM00Data)
    self:AdjustItems(MM01Data)
    self:AdjustItems(MM02Data)
    self:AdjustItems(MM03Data)
    self:AdjustItems(MM04Data)
    self:AdjustItems(MM05Data)
    self:AdjustItems(MM06Data)
    self:AdjustItems(MM07Data)
    self:AdjustItems(MM08Data)
    self:AdjustItems(MM09Data)
    self:AdjustItems(MM10Data)
    self:AdjustItems(MM11Data)
    self:AdjustItems(MM12Data)
    self:AdjustItems(MM13Data)
    self:AdjustItems(MM14Data)
    self:AdjustItems(MM15Data)
  end

  -- Check for and reindex if the item structure has changed
  self:ReIndexSales(MM00Data)
  self:ReIndexSales(MM01Data)
  self:ReIndexSales(MM02Data)
  self:ReIndexSales(MM03Data)
  self:ReIndexSales(MM04Data)
  self:ReIndexSales(MM05Data)
  self:ReIndexSales(MM06Data)
  self:ReIndexSales(MM07Data)
  self:ReIndexSales(MM08Data)
  self:ReIndexSales(MM09Data)
  self:ReIndexSales(MM10Data)
  self:ReIndexSales(MM11Data)
  self:ReIndexSales(MM12Data)
  self:ReIndexSales(MM13Data)
  self:ReIndexSales(MM14Data)
  self:ReIndexSales(MM15Data)

  -- Bring seperate lists together we can still access the sales history all together
  self:ReferenceSales(MM00Data)
  self:ReferenceSales(MM01Data)
  self:ReferenceSales(MM02Data)
  self:ReferenceSales(MM03Data)
  self:ReferenceSales(MM04Data)
  self:ReferenceSales(MM05Data)
  self:ReferenceSales(MM06Data)
  self:ReferenceSales(MM07Data)
  self:ReferenceSales(MM08Data)
  self:ReferenceSales(MM09Data)
  self:ReferenceSales(MM10Data)
  self:ReferenceSales(MM11Data)
  self:ReferenceSales(MM12Data)
  self:ReferenceSales(MM13Data)
  self:ReferenceSales(MM14Data)
  self:ReferenceSales(MM15Data)

  self.systemSavedVariables.dataLocations = self.systemSavedVariables.dataLocations or {}
  self.systemSavedVariables.dataLocations[GetWorldName()] = true

  if GuildSalesAssistant and GuildSalesAssistant.MasterMerchantEdition then
      GuildSalesAssistant:InitializeMM()
      GuildSalesAssistant:LoadInitialData(self.salesData)
  end

  if not self.systemSavedVariables.delayInit then
    self:TruncateHistory()
    self:InitItemHistory()
    self:indexHistoryTables()
  else
    -- Queue them for later
    local LEQ = LibExecutionQueue:new()
    LEQ:Add(function () self:TruncateHistory() end, 'TruncateHistory')
    LEQ:Add(function () self:InitItemHistory() end, 'InitItemHistory')
    LEQ:Add(function () self:indexHistoryTables() end, 'indexHistoryTables')
    LEQ:Add(function () self:InitScrollLists() end, 'InitScrollLists')
  end

  -- We'll grab their locale now, it's really only used for a couple things as
  -- most localization is handled by the i18n/$(language).lua files
  -- Defaults to English because bias, that's why. :P
  self.locale = GetCVar('Language.2')
  if self.locale ~= 'en' and self.locale ~= 'de' and self.locale ~= 'fr' then
    self.locale = 'en'
  end

  self:setupGuildColors()

  -- Setup the options menu and main windows
  self:LibAddonInit()
  self:SetupMasterMerchantWindow()
  self:RestoreWindowPosition()

  -- Add the MasterMerchant window to the mail and trading house scenes if the
  -- player's settings indicate they want that behavior
  self.uiFragment = ZO_FadeSceneFragment:New(MasterMerchantWindow)
  self.guildUiFragment = ZO_FadeSceneFragment:New(MasterMerchantGuildWindow)

  LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_MOUSE_UP_EVENT, self.LinkHandler_OnLinkMouseUp)

  ZO_PreHook('ZO_InventorySlot_ShowContextMenu', function(rowControl) self:myZO_InventorySlot_ShowContextMenu(rowControl) end)

  local settingsToUse = MasterMerchant:ActiveSettings()
  local theFragment = ((settingsToUse.viewSize == ITEMS) and self.uiFragment) or ((settingsToUse.viewSize == GUILDS) and self.guildUiFragment) or self.listingUiFragment
    if settingsToUse.openWithMail then
    MAIL_INBOX_SCENE:AddFragment(theFragment)
    MAIL_SEND_SCENE:AddFragment(theFragment)
  end

  if settingsToUse.openWithStore then
    TRADING_HOUSE_SCENE:AddFragment(theFragment)
  end

  -- Because we allow manual toggling of the MasterMerchant window in those scenes (without
  -- making that setting permanent), we also have to hide the window on closing them
  -- if they're not part of the scene.
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_MAIL_CLOSE_MAILBOX, function()
    if not settingsToUse.openWithMail then
      self:ActiveWindow():SetHidden(true)
      MasterMerchantStatsWindow:SetHidden(true)
    end
  end)
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_CLOSE_TRADING_HOUSE, function()
    MasterMerchant.ClearDealInfoCache()
    if not settingsToUse.openWithStore then
      self:ActiveWindow():SetHidden(true)
      MasterMerchantStatsWindow:SetHidden(true)
    end
  end)

  -- We also want to make sure the MasterMerchant windows are hidden in the game menu
  ZO_PreHookHandler(ZO_GameMenu_InGame, 'OnShow', function()
    self:ActiveWindow():SetHidden(true)
    MasterMerchantStatsWindow:SetHidden(true)
    MasterMerchantFeedback:SetHidden(true)
  end)

  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_TRADING_HOUSE_PENDING_ITEM_UPDATE, function (eventCode, slotId, isPending)
    if settingsToUse.showCalc and isPending and GetSlotStackSize(1, slotId) > 1 then
      local theLink = GetItemLink(1, slotId, LINK_STYLE_DEFAULT)
      local theIID = GetItemLinkItemId(itemLink)
      local theIData = self.makeIndexFromLink(theLink)
      local postedStats = self:toolTipStats(theIID, theIData)
      MasterMerchantPriceCalculatorStack:SetText(GetString(MM_APP_TEXT_TIMES) .. GetSlotStackSize(1, slotId))
      local floorPrice = 0
      if postedStats.avgPrice then floorPrice = string.format('%.2f', postedStats['avgPrice']) end
      MasterMerchantPriceCalculatorUnitCostAmount:SetText(floorPrice)
      MasterMerchantPriceCalculatorTotal:SetText(GetString(MM_TOTAL_TITLE) .. self.LocalizedNumber(math.floor(floorPrice * GetSlotStackSize(1, slotId))) .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')
      MasterMerchantPriceCalculator:SetHidden(false)
    else MasterMerchantPriceCalculator:SetHidden(true) end
  end)

  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_TRADING_HOUSE_RESPONSE_RECEIVED, function (_, responseType, result)
    if responseType == TRADING_HOUSE_RESULT_POST_PENDING and result == TRADING_HOUSE_RESULT_SUCCESS then MasterMerchantPriceCalculator:SetHidden(true) end
    -- Set up guild store buying advice
    self:initBuyingAdvice()
    self:initSellingAdvice()
  end)

  -- I could do this with action layer pop/push, but it's kind've a pain
  -- when it's just these I want to hook
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_CLOSE_BANK, function() self:ActiveWindow():SetHidden(true) end)
--    MasterMerchantWindow:SetHidden(true)
--    MasterMerchantGuildWindow:SetHidden(true)
--  end)
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_CLOSE_GUILD_BANK, function() self:ActiveWindow():SetHidden(true) end)
--    MasterMerchantWindow:SetHidden(true)
--    MasterMerchantGuildWindow:SetHidden(true)
--  end)
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_CLOSE_STORE, function() self:ActiveWindow():SetHidden(true) end)
--    MasterMerchantWindow:SetHidden(true)
--    MasterMerchantGuildWindow:SetHidden(true)
--  end)
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_END_CRAFTING_STATION_INTERACT, function() self:ActiveWindow():SetHidden(true) end)
--    MasterMerchantWindow:SetHidden(true)
--    MasterMerchantGuildWindow:SetHidden(true)
--  end)

  -- We'll add stats to tooltips for items we have data for, if desired
  ZO_PreHookHandler(PopupTooltip, 'OnUpdate', function() self:addStatsPopupTooltip(PopupTooltip) end)
	ZO_PreHookHandler(PopupTooltip, 'OnHide', function() self:remStatsPopupTooltip(PopupTooltip) end)
  ZO_PreHookHandler(ItemTooltip, 'OnUpdate', function() self:addStatsItemTooltip() end)
  ZO_PreHookHandler(ItemTooltip, 'OnHide', function() self:remStatsItemTooltip() end)

  ZO_PreHookHandler(ZO_ProvisionerTopLevelTooltip, 'OnUpdate', function() self:addStatsPopupTooltip(ZO_ProvisionerTopLevelTooltip) end)
  ZO_PreHookHandler(ZO_ProvisionerTopLevelTooltip, 'OnHide', function() self:remStatsPopupTooltip(ZO_ProvisionerTopLevelTooltip) end)

  if TRADING_HOUSE then
    OriginalSetupPendingPost = TRADING_HOUSE.SetupPendingPost
    TRADING_HOUSE.SetupPendingPost = MasterMerchant.SetupPendingPost
    ZO_PreHook(TRADING_HOUSE, 'PostPendingItem', MasterMerchant.PostPendingItem)
  end

  -- Set up GM Tools, if also installed
  self:initGMTools()

  -- Set up purchase tracking, if also installed
  self:initPurchaseTracking()

  --Watch inventory listings
  for _,i in pairs(PLAYER_INVENTORY.inventories) do
		local listView = i.listView
		if listView and listView.dataTypes and listView.dataTypes[1] then
			local originalCall = listView.dataTypes[1].setupCallback

			listView.dataTypes[1].setupCallback = function(control, slot)
				originalCall(control, slot)
        self:SwitchPrice(control, slot)
			end
		end
	end

  -- Watch Decon list
  local originalCall = ZO_SmithingTopLevelDeconstructionPanelInventoryBackpack.dataTypes[1].setupCallback
	ZO_SmithingTopLevelDeconstructionPanelInventoryBackpack.dataTypes[1].setupCallback = function(control, slot)
		originalCall(control, slot)
		self:SwitchPrice(control, slot)
	end

  -- Right, we're all set up, so wait for the player activated event
  -- and then do an initial (deep) scan in case it's been a while since the player
  -- logged on, then use RegisterForUpdate to set up a timed scan.
	EVENT_MANAGER:RegisterForEvent(MasterMerchant.name.."_DeepScan", EVENT_PLAYER_ACTIVATED, function()

    EVENT_MANAGER:UnregisterForEvent(MasterMerchant.name.."_DeepScan", EVENT_PLAYER_ACTIVATED )

    --[[self:playSounds()
    local mmPlaySound = PlaySound
    PlaySound = function(soundId)
      mmPlaySound(soundId)
      d(soundId)
    end

    local mmPlaySoundQueue = ZO_QueuedSoundPlayer.PlaySound
    ZO_QueuedSoundPlayer.PlaySound = function(self, soundName, soundLength)
      mmPlaySoundQueue(self,soundName, soundLength)
      d(MasterMerchant.concat(soundName, soundLength))
    end
    --]]

    if false and self.savedVariables.autoNext then

      local localRunInitialSetup = TRADING_HOUSE.RunInitialSetup
      TRADING_HOUSE.RunInitialSetup = function (self, ...)
        localRunInitialSetup(self, ...)

        local localOriginalPrevious = TRADING_HOUSE.m_search.SearchPreviousPage
        TRADING_HOUSE.m_search.SearchPreviousPage = function (self, ...)
          MasterMerchant.lastDirection = -1
          localOriginalPrevious(self, ...)
        end

        local localOriginalNext = TRADING_HOUSE.m_search.SearchNextPage
        TRADING_HOUSE.m_search.SearchNextPage = function (self, ...)
          MasterMerchant.lastDirection = 1
          localOriginalNext(self, ...)
        end

        local localDoSearch = TRADING_HOUSE.m_search.DoSearch
        TRADING_HOUSE.m_search.DoSearch = function (self, ...)
          MasterMerchant.lastDirection = 1
          localDoSearch(self, ...)
        end

        local originalOnSearchCooldownUpdate = TRADING_HOUSE.OnSearchCooldownUpdate
        TRADING_HOUSE.OnSearchCooldownUpdate = function (self, ...)
          originalOnSearchCooldownUpdate(self, ...)
          if GetTradingHouseCooldownRemaining() == 0 then
            if zo_plainstrfind(self.m_resultCount:GetText(), '(0)') and self.m_search:HasNextPage() and (MasterMerchant.lastDirection == 1) then
              self.m_search:SearchNextPage()
            end
            if zo_plainstrfind(self.m_resultCount:GetText(), '(0)') and self.m_search:HasPreviousPage() and (MasterMerchant.lastDirection == -1) then
              MasterMerchant.lastDirection = 0
              self.m_search:SearchPreviousPage()
            end
          end
        end
      end
    end

    if self.systemSavedVariables.delayInit then
      -- Finish the init after the player has loaded....
      zo_callLater(function()
          MasterMerchant.v(2, "|cFFFF00Master Merchant Initializing...|r")
          local LEQ = LibExecutionQueue:new()
          LEQ:Start()
      end, 10)
    else
      -- The others were already done...
      self:InitScrollLists()
    end

	end)
end

function MasterMerchant:SwitchPrice(control, slot)
  if MasterMerchant:ActiveSettings().replaceInventoryValues then
    local bagId = control.dataEntry.data.bagId
	  local slotIndex = control.dataEntry.data.slotIndex
	  local itemLink = bagId and GetItemLink(bagId, slotIndex) or GetItemLink(slotIndex)

    if itemLink then
      local theIID = GetItemLinkItemId(itemLink)
      local itemIndex = MasterMerchant.makeIndexFromLink(itemLink)
      local tipStats = MasterMerchant:toolTipStats(theIID, itemIndex, true, true)
      if tipStats.avgPrice then
          --[[
          if control.dataEntry.data.rawName == "Fortified Nirncrux" then
          MasterMerchant.ShowChildren(control, 20)
          --d(control.dataEntry.data.rawName)
          d(control.dataEntry.data.bagId)
          d(control.dataEntry.data.slotIndex)
          d(control.dataEntry.data.statPrice)
          d(control.dataEntry.data.sellPrice)
          d(control.dataEntry.data.stackSellPrice)
          --d(control.dataEntry.data)
          end
          --]]
          if not control.dataEntry.data.mmOriginalPrice then
            control.dataEntry.data.mmOriginalPrice = control.dataEntry.data.sellPrice
            control.dataEntry.data.mmOriginalStackPrice = control.dataEntry.data.stackSellPrice
          end

          control.dataEntry.data.mmPrice = tonumber(string.format('%.0f',tipStats.avgPrice))
          control.dataEntry.data.stackSellPrice = tonumber(string.format('%.0f',tipStats.avgPrice * control.dataEntry.data.stackCount))
          control.dataEntry.data.sellPrice = control.dataEntry.data.mmPrice

          local sellPriceControl = control:GetNamedChild("SellPrice")
          if (sellPriceControl) then
            sellPrice = MasterMerchant.LocalizedNumber(control.dataEntry.data.stackSellPrice)
            sellPrice = '|cEEEE33' .. sellPrice .. '|r |t16:16:EsoUI/Art/currency/currency_gold.dds|t'
            sellPriceControl:SetText(sellPrice)
	        end
      else
          if control.dataEntry.data.mmOriginalPrice then
            control.dataEntry.data.sellPrice = control.dataEntry.data.mmOriginalPrice
            control.dataEntry.data.stackSellPrice = control.dataEntry.data.mmOriginalStackPrice
          end
          local sellPriceControl = control:GetNamedChild("SellPrice")
          if (sellPriceControl) then
            sellPrice = string.format('%.0f', control.dataEntry.data.stackSellPrice)
            sellPrice = MasterMerchant.LocalizedNumber(sellPrice)
            sellPrice = sellPrice .. '|t16:16:EsoUI/Art/currency/currency_gold.dds|t'
            sellPriceControl:SetText(sellPrice)
	        end
      end
    end
  end
end

function MasterMerchant:TruncateHistory()

  -- DEBUG  TruncateHistory
  -- do return end

  local prefunc = function(extraData)
    extraData.start = GetTimeStamp()
    extraData.deleteCount = 0
    extraData.epochBack = GetTimeStamp() - (86400 * self.systemSavedVariables.historyDepth)

    self:setScanning(true)
  end

  local loopfunc = function(itemid, versionid, versiondata, saleid, saledata, extraData)

    local salesCount = MasterMerchant.NonContiguousNonNilCount(versiondata['sales'])
    for saleid, saledata in MasterMerchant.spairs(versiondata['sales'], function(a, b) return MasterMerchant.CleanTimestamp(a) < MasterMerchant.CleanTimestamp(b) end) do
      if salesCount > self.systemSavedVariables.minItemCount and
        ( salesCount > self.systemSavedVariables.maxItemCount
          or saledata['timestamp'] == nil
          or type(saledata['timestamp']) ~= 'number'
          or saledata['timestamp'] < extraData.epochBack
        ) then
          -- Remove it by setting it to nil
          versiondata['sales'][saleid] = nil
          extraData.deleteCount = extraData.deleteCount + 1
          salesCount = salesCount - 1
      end
    end
    return true

  end

  local postfunc = function(extraData)

    extraData.muleIdCount = 0
    if extraData.deleteCount > 0 then
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM00Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM01Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM02Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM03Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM04Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM05Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM06Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM07Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM08Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM09Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM10Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM11Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM12Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM13Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM14Data.savedVariables.SalesData)
      extraData.muleIdCount = extraData.muleIdCount + self:CleanMule(MM15Data.savedVariables.SalesData)
    end
    self:setScanning(false)


    MasterMerchant.v(4, 'Trimming: ' .. GetTimeStamp() - extraData.start .. ' seconds to trim:')
    MasterMerchant.v(4, '  ' .. extraData.deleteCount .. ' old records removed.')

    if GuildSalesAssistant and GuildSalesAssistant.MasterMerchantEdition then
      GuildSalesAssistant:TrimHistory(extraData.epochBack)
    end
  end

  if not self.isScanning then
    self:iterateOverSalesData(nil, nil, nil, prefunc, loopfunc, postfunc, {} )
  end

end


function MasterMerchant:InitItemHistory()

  local extradata = {}

  if self.guildItems == nil then
    self.guildItems = {}
    extradata.doGuildItems = true
  end

  if self.myItems == nil then
    self.myItems = {}
    extradata.doMyItems = true
    extradata.playerName = string.lower(GetDisplayName())
  end

  if self.guildSales == nil then
    self.guildSales = {}
    extradata.doGuildSales = true
  end

  if self.guildPurchases == nil then
    self.guildPurchases = {}
    extradata.doGuildPurchases = true
  end

  if (extradata.doGuildItems or extradata.doMyItems or extradata.doGuildSales or extradata.doGuildPurchases) then

    self.totalRecords = 0
    local prefunc = function(extraData)
      extraData.start = GetTimeStamp()
      self:setScanning(true)
    end

    local loopfunc = function(itemid, versionid, versiondata, saleid, saledata, extraData)
      self.totalRecords = self.totalRecords + 1
      if (not (saledata == {})) and saledata.guild then
        if (extradata.doGuildItems) then
          self.guildItems[saledata.guild] = self.guildItems[saledata.guild] or MMGuild:new(saledata.guild)
          local guild = self.guildItems[saledata.guild]
          local _, firstsaledata = next(versiondata.sales, nil)
          guild:addSaleByDate(firstsaledata.itemLink, saledata.timestamp, saledata.price, saledata.quant, false, false, MasterMerchant.concat(versiondata.itemDesc, versiondata.itemAdderText))
        end

        if (extradata.doMyItems and string.lower(saledata.seller) == extradata.playerName) then
          self.myItems[saledata.guild] = self.myItems[saledata.guild] or MMGuild:new(saledata.guild)
          local guild = self.myItems[saledata.guild]
          local _, firstsaledata = next(versiondata.sales, nil)
          guild:addSaleByDate(firstsaledata.itemLink, saledata.timestamp, saledata.price, saledata.quant, false, false, MasterMerchant.concat(versiondata.itemDesc, versiondata.itemAdderText))
        end

        if (extradata.doGuildSales) then
          self.guildSales[saledata.guild] = self.guildSales[saledata.guild] or MMGuild:new(saledata.guild)
          local guild = self.guildSales[saledata.guild]
          guild:addSaleByDate(saledata.seller, saledata.timestamp, saledata.price, saledata.quant, false, false)
        end

        if (extradata.doGuildPurchases) then
          self.guildPurchases[saledata.guild] = self.guildPurchases[saledata.guild] or MMGuild:new(saledata.guild)
          local guild = self.guildPurchases[saledata.guild]
          guild:addSaleByDate(saledata.buyer, saledata.timestamp, saledata.price, saledata.quant, saledata.wasKiosk, false)
        end
      end
      return false
    end

    local postfunc = function(extraData)

      if (extradata.doGuildItems) then
        for _, guild in pairs(self.guildItems) do
          guild:sort()
        end
      end

      if (extradata.doMyItems) then
        for _, guild in pairs(self.myItems) do
          guild:sort()
        end
      end

      if (extradata.doGuildSales) then
        for guildName, guild in pairs(self.guildSales) do
          guild:sort()
        end
      end

      if (extradata.doGuildPurchases) then
        for _, guild in pairs(self.guildPurchases) do
          guild:sort()
        end
      end

      -- Set up guild roster info
      if self.savedVariables.diplayGuildInfo then
        self:initRosterStats()
      end

      self:setScanning(false)

      MasterMerchant.v(5, 'Init Guild and Item totals: ' .. GetTimeStamp() - extraData.start .. ' seconds to init ' .. self.totalRecords .. ' records.')
    end

    if not self.isScanning then
      self:iterateOverSalesData(nil, nil, nil, prefunc, loopfunc, postfunc, extradata )
    end

  end
 end

function MasterMerchant:InitScrollLists()

    self:SetupScrollLists()

    local numGuilds = GetNumGuilds()
    for i = 1, numGuilds do
      local guildID = GetGuildId(i)
      local guildName = GetGuildName(guildID)
      MasterMerchant.lastHistoryRequest[guildID] = GetTimeStamp()
      MasterMerchant.lastHeadEvent[guildID] = 0
      MasterMerchant.alertQueue[guildName] = {}
      if MasterMerchant.eventsSinceCache[guildID] == nil then MasterMerchant.eventsSinceCache[guildID] = {} end
    end

    MasterMerchant.v(2, '|cFFFF00Master Merchant Initialized -- Holding information on ' .. self.totalRecords .. ' sales.|r')

    self.isFirstScan = self.savedVariables.offlineSales
    if NonContiguousCount(self.salesData) > 0 then
      self.veryFirstScan = false
    else
      self.veryFirstScan = true
      -- Scan back 3 days on inital startup
      local checkTime = GetTimeStamp() - (24 * 3 * 3600)
      local guildNum = 1
      while guildNum <= GetNumGuilds() do
        local guildID = GetGuildId(guildNum)
        local guildName = GetGuildName(guildID)
        MasterMerchant.systemSavedVariables.lastScan[guildName] = checkTime
        MasterMerchant.systemSavedVariables.newestItem[guildName] = checkTime
        guildNum = guildNum + 1
      end

      MasterMerchant.v(2, MasterMerchant.concat(GetString(MM_APP_MESSAGE_NAME), GetString(SK_FIRST_SCAN)))
    end
    self:ScanStoresParallel(true)

    MasterMerchant.isInitialized = true

end

local dealInfoCache = {}
MasterMerchant.ClearDealInfoCache = function()
	ZO_ClearTable(dealInfoCache)
end

MasterMerchant.GetDealInfo = function(itemLink, purchasePrice, stackCount)
  local key = string.format("%s_%d_%d", itemLink, purchasePrice, stackCount)
  if(not dealInfoCache[key]) then
    local setPrice = nil
    local salesCount = 0
    local theIID = GetItemLinkItemId(itemLink)
    local itemIndex = MasterMerchant.makeIndexFromLink(itemLink)
    local tipStats = MasterMerchant:toolTipStats(theIID, itemIndex, true)
    if tipStats.avgPrice then
      setPrice = tipStats['avgPrice']
      salesCount = tipStats['numSales']
    end
    dealInfoCache[key] = {MasterMerchant.DealCalc(setPrice, salesCount, purchasePrice, stackCount)}
  end
  return unpack(dealInfoCache[key])
end

function MasterMerchant:SendNote(gold)
  MasterMerchantFeedback:SetHidden(true)
  SCENE_MANAGER:Show('mailSend')
  ZO_MailSendToField:SetText('@Sharlikran')
  ZO_MailSendSubjectField:SetText('Master Merchant')
  QueueMoneyAttachment(gold)
  ZO_MailSendBodyField:TakeFocus()
end

Original_ZO_InventorySlotActions_Show = ZO_InventorySlotActions.Show

function ZO_InventorySlotActions:Show()
  g_slotActions = self
  Original_ZO_InventorySlotActions_Show(self)
end

-------------------------------------------------------------------------------
-- LMP - Removed Fonts v1.1
-------------------------------------------------------------------------------
--
-- Copyright (c) 2014 Ales Machat (Garkin)
--
-- Permission is hereby granted, free of charge, to any person
-- obtaining a copy of this software and associated documentation
-- files (the 'Software'), to deal in the Software without
-- restriction, including without limitation the rights to use,
-- copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following
-- conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
-- OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
-- HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
-- WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
-- OTHER DEALINGS IN THE SOFTWARE.


local function OnAddOnLoaded(eventCode, addOnName)
   if addOnName:find('^ZO_') then return end
   if addOnName == MasterMerchant.name then
        MasterMerchant:Initialize()
        -- Set up /mm as a slash command toggle for the main window
        SLASH_COMMANDS['/mm'] = MasterMerchant.Slash
   elseif addOnName == "AwesomeGuildStore" then
     -- Set up AGS integration, if it's installed
     MasterMerchant:initAGSIntegration()
   end

   --if the first loaded version of LibMediaProvider was r6 and older, fonts are
   --already registered, but with invalid paths.
   if LMP.MediaTable.font['Arial Narrow']     then LMP.MediaTable.font['Arial Narrow']     = 'MasterMerchant/Fonts/arialn.ttf'               end
   if LMP.MediaTable.font['ESO Cartographer'] then LMP.MediaTable.font['ESO Cartographer'] = 'MasterMerchant/Fonts/esocartographer-bold.otf' end
   if LMP.MediaTable.font['Fontin Bold']      then LMP.MediaTable.font['Fontin Bold']      = 'MasterMerchant/Fonts/fontin_sans_b.otf'        end
   if LMP.MediaTable.font['Fontin Italic']    then LMP.MediaTable.font['Fontin Italic']    = 'MasterMerchant/Fonts/fontin_sans_i.otf'        end
   if LMP.MediaTable.font['Fontin Regular']   then LMP.MediaTable.font['Fontin Regular']   = 'MasterMerchant/Fonts/fontin_sans_r.otf'        end
   if LMP.MediaTable.font['Fontin SmallCaps'] then LMP.MediaTable.font['Fontin SmallCaps'] = 'MasterMerchant/Fonts/fontin_sans_sc.otf'       end

   --LMP r7 and above doesn't have fonts registered yet
   LMP:Register('font', 'Arial Narrow',           'MasterMerchant/Fonts/arialn.ttf')
   LMP:Register('font', 'ESO Cartographer',       'MasterMerchant/Fonts/esocartographer-bold.otf')
   LMP:Register('font', 'Fontin Bold',            'MasterMerchant/Fonts/fontin_sans_b.otf')
   LMP:Register('font', 'Fontin Italic',          'MasterMerchant/Fonts/fontin_sans_i.otf')
   LMP:Register('font', 'Fontin Regular',         'MasterMerchant/Fonts/fontin_sans_r.otf')
   LMP:Register('font', 'Fontin SmallCaps',       'MasterMerchant/Fonts/fontin_sans_sc.otf')

   --this game font is missing in all versions of LMP
   LMP:Register('font', 'Futura Condensed Bold',  'EsoUI/Common/Fonts/FuturaStd-CondensedBold.otf')
end


-- Event handler for the OnAddOnLoaded event
--function MasterMerchant.OnAddOnLoaded(event, addonName)
--  if addonName == MasterMerchant.name then
--    MasterMerchant:Initialize()
----end
--end
function MasterMerchant.Slash(allArgs)
  local args = ""
  local guildNumber = 0
  local hoursBack = 0
  local argNum = 0
  for w in string.gmatch(allArgs,"%w+") do
    argNum = argNum + 1
    if argNum == 1 then args = w end
    if argNum == 2 then guildNumber = tonumber(w) end
    if argNum == 3 then hoursBack = tonumber(w) end
  end
  args = string.lower(args)

  if args == 'help' then
    MasterMerchant.v(1, "/mm  - show/hide the main Master Merchant window")
    MasterMerchant.v(1, "/mm dups  - scans your history to purge duplicate entries")
    MasterMerchant.v(1, "/mm clean - cleans out bad sales records (invalid information)")
    MasterMerchant.v(1, "/mm clearprices  - clears your historical listing prices")
    MasterMerchant.v(1, "/mm invisible  - resets the MM window positions in case they are invisible (aka off the screen)")
    MasterMerchant.v(1, "/mm export <Guild number>  - 'exports' last weeks sales/purchase totals for the guild")
    MasterMerchant.v(1, "/mm sales <Guild number>  - 'exports' sales activity data for your guild")
    MasterMerchant.v(1, "/mm verbose <setting 1-6>  - sets MM message verbosity: 1 - Nearly Silent to 6 - Debugging Level Info.")

    MasterMerchant.v(1, "/mm deal  - toggles deal display between margin % and profit in the guild stores")
    MasterMerchant.v(1, "/mm types  - list the item type filters that are available")
    MasterMerchant.v(1, "/mm traits  - list the item trait filters that are available")
    MasterMerchant.v(1, "/mm quality  - list the item quality filters that are available")
    MasterMerchant.v(1, "/mm equip  - list the item equipment type filters that are available")
    MasterMerchant.v(1, "/mm slide  - relocates your sales records to a new @name (Ex. @kindredspiritgr to @kindredspiritgrSlid)  /mm slideback to reverse.")
    return
  end

  if args == 'dups' or args == 'stilldups' then
    if MasterMerchant.isScanning then
        if args == 'dups' then MasterMerchant.v(2, "Purging of duplicate sales records will begin when current scan completes.") end
        zo_callLater(function() MasterMerchant.Slash('stilldups') end, 10000)
        return
    end
    MasterMerchant.v(2, "Purging duplicates.")
    MasterMerchant:PurgeDups()
    return
  end
  if args == 'slide' or args == 'kindred' or args == 'stillslide' then
    if MasterMerchant.isScanning then
        if args ~= 'stillslide' then MasterMerchant.v(2, "Sliding of your sales records will begin when current scan completes.") end
        zo_callLater(function() MasterMerchant.Slash('stillslide') end, 10000)
        return
    end
    MasterMerchant.v(2, "Sliding your sales.")
    MasterMerchant:SlideSales(false)
    return
  end

  if args == 'slideback' or args == 'kindredback' or args == 'stillslideback' then
    if MasterMerchant.isScanning then
        if args ~= 'stillslideback' then MasterMerchant.v(2, "Sliding of your sales records will begin when current scan completes.") end
        zo_callLater(function() MasterMerchant.Slash('stillslideback') end, 10000)
        return
    end
    MasterMerchant.v(2, "Sliding your sales.")
    MasterMerchant:SlideSales(true)
    return
  end

  if args == 'export' then
    MasterMerchant.guildNumber = guildNumber
    if MasterMerchant.guildNumber or 0 > 0 then
      MasterMerchant.v(2, "'Exporting' last weeks sales/purchase/rank data.")
      MasterMerchant:ExportLastWeek()
      MasterMerchant.v(2, "Export complete.  /reloadui to save the file.")
    else
      MasterMerchant.v(2, "Please include the guild number you wish to export.")
    end
    return
  end

  if args == 'sales' then
    MasterMerchant.guildNumber = guildNumber
    if MasterMerchant.guildNumber or 0 > 0 then
      MasterMerchant.v(2, "'Exporting' sales activity.")
      MasterMerchant:ExportSalesData()
      MasterMerchant.v(2, "Export complete.  /reloadui to save the file.")
    else
      MasterMerchant.v(2, "Please include the guild number you wish to export.")
    end
    return
  end

  if args == '42' then
    MasterMerchant:SpecialMessage(true)
    return
  end

  if args == 'verbose' then
    if guildNumber == nil then guildNumber = 1 end
    if guildNumber >= 1 and guildNumber <= 7 then
      MasterMerchant:ActiveSettings().verbose = guildNumber
      MasterMerchant.savedVariables.verbose = guildNumber
      MasterMerchant.verboseLevel = guildNumber
      MasterMerchant.v(2, "Verbosity setting changed.")
    else
      MasterMerchant.v(2, "Verbosity setting must be between 1 and 7.")
    end
    return
  end

  if args == 'clean' or args == 'stillclean' then
    if MasterMerchant.isScanning then
        if args == 'clean' then MasterMerchant.v(2, "Cleaning out bad sales records will begin when current scan completes.") end
        zo_callLater(function() MasterMerchant.Slash('stillclean') end, 10000)
        return
    end
    MasterMerchant.v(2, "Cleaning Out Bad Records.")
    MasterMerchant:CleanOutBad()
    return
  end
  if args == 'clearprices' then
    MasterMerchant:ActiveSettings().pricingData = {}
    MasterMerchant.v(2, "Your prices have been cleared.")
    return
  end
  if args == 'invisible' then
    MasterMerchantWindow:ClearAnchors()
    MasterMerchantWindow:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, 30, 30)
    MasterMerchantGuildWindow:ClearAnchors()
    MasterMerchantGuildWindow:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, 30, 30)
    MasterMerchant:ActiveSettings().winLeft=30
    MasterMerchant:ActiveSettings().guildWinLeft=30
    MasterMerchant:ActiveSettings().winTop=30
    MasterMerchant:ActiveSettings().guildWinTop=30
    MasterMerchant.v(2, "Your MM window positions have been reset.")
    return
  end
  if args == 'deal' or args == 'saucy' then
    MasterMerchant:ActiveSettings().saucy = not MasterMerchant:ActiveSettings().saucy
    MasterMerchant.v(2, "Guild listing display switched.")
    return
  end
  if args == 'types' then
    local message = 'Item types: '
    for i = 0, 64 do
      message = message .. i .. ')' .. GetString("SI_ITEMTYPE", i) .. ', '
    end
    MasterMerchant.v(2, message)
    return
  end
  if args == 'traits' then
    local message = 'Item traits: '
    for i = 0, 32 do
      message = message .. i .. ')' .. GetString("SI_ITEMTRAITTYPE", i) .. ', '
    end
    MasterMerchant.v(2, message)
    return
  end
  if args == 'quality' then
    local message = 'Item quality: '
    for i = 0, 5 do
      message = message .. GetString("SI_ITEMQUALITY", i) .. ', '
    end
    MasterMerchant.v(2, message)
    return
  end
  if args == 'equip' then
    local message = 'Equipment types: '
    for i = 0, 14 do
      message = message .. GetString("SI_EQUIPTYPE", i) .. ', '
    end
    MasterMerchant.v(2, message)
    return
  end

  MasterMerchant:ToggleMasterMerchantWindow()
end

-- Register for the OnAddOnLoaded event
EVENT_MANAGER:RegisterForEvent(MasterMerchant.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)

function MasterMerchant:PlayerLoaded(_, initial)
    if initial then
      --MasterMerchant.dm("Debug", "PlayerLoaded")
      local guildNum = GetNumGuilds()
      if ShopkeeperSavedVars == nil then ShopkeeperSavedVars = {} end
      if ShopkeeperSavedVars["Default"] == nil then ShopkeeperSavedVars["Default"] = {} end
      if ShopkeeperSavedVars["Default"]["MasterMerchant"] == nil then ShopkeeperSavedVars["Default"]["MasterMerchant"] = {} end
      if ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"] == nil then ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"] = {} end
      if ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"] == nil then ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"] = {} end
      if ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"] == nil then ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"] = {} end

      for i = 1, guildNum do
        local guildID = GetGuildId(i)
        local guildName = GetGuildName(guildID)
        ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["numEvents"][guildName] = 1
        ShopkeeperSavedVars["Default"]["MasterMerchant"]["$AccountWide"]["lastNonDuplicate"][guildName] = 1
      end
    end
  EVENT_MANAGER:UnregisterForEvent(MasterMerchant.name.."_Initial", EVENT_PLAYER_ACTIVATED)
end
