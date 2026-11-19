-- GameData : achat en gros chez un marchand. Le jeu n'achète qu'une pile par appel (4 lots de 5 épices = 20) : on
-- enchaîne les appels, une pile à la fois, en attendant que les sacs soient à jour avant la suivante.
--   Alt + clic sur un article du marchand : « combien ? », puis achat.  /gdata stop : arrêter.
-- Une seule action de ta part (le clic) ; l'achat chez un marchand n'est pas une action protégée par le jeu, et c'est
-- ce que font les add-ons d'achat en gros. Arrêt automatique : quantité atteinte, plus d'or, sacs pleins, marchand fermé.
local _, ns = ...

local WAIT = 1.5 -- au plus 1,5 s d'attente des sacs entre deux piles

local function merchantIndex(id)
  for i = 1, GetMerchantNumItems() do
    if GetMerchantItemID(i) == id then return i end
  end
end
ns.merchantIndex = merchantIndex

-- Unités de cet objet qui tiennent encore dans les sacs (cases vides des sacs ordinaires + piles entamées).
function ns.freeUnits(id, stack)
  local units = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local free, bagType = C_Container.GetContainerNumFreeSlots(bag)
    if (bagType or 0) == 0 then units = units + (free or 0) * stack end
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local it = C_Container.GetContainerItemInfo(bag, slot)
      if it and it.itemID == id and it.stackCount < stack then units = units + stack - it.stackCount end
    end
  end
  return units
end

local job
local function stop(reason)
  if not job then return end
  print(("GameData : achat de %s arrêté — %d acheté(s) sur %d (%s)."):format(job.name, job.bought, job.wanted, reason))
  job.ticker:Cancel()
  job = nil
end
ns.stopBulkBuy = function() stop("arrêté à la main") end

local function step()
  if not (MerchantFrame and MerchantFrame:IsShown()) then return stop("marchand fermé") end
  if job.waiting and GetTime() - job.waiting < WAIT then return end
  job.waiting = nil
  local index = merchantIndex(job.id)
  if not index then return stop("plus vendu ici") end
  local info = C_MerchantFrame.GetItemInfo(index)
  local lot, per = math.max(1, info.stackCount or 1), GetMerchantItemMaxStack(index)
  local q = math.min(job.wanted - job.bought, math.max(lot, per))
  q = math.min(q, math.floor(GetMoney() / (info.price / lot)))
  q = math.min(q, ns.freeUnits(job.id, math.max(per, lot)))
  q = math.floor(q / lot) * lot -- lots entiers du marchand
  if q <= 0 then
    if job.bought >= job.wanted then
      print(("GameData : %d × %s achetés."):format(job.bought, job.name))
      job.ticker:Cancel()
      job = nil
      return
    end
    return stop(GetMoney() < info.price and "plus assez d'or" or "sacs pleins")
  end
  BuyMerchantItem(index, q)
  job.bought, job.waiting, job.calls = job.bought + q, GetTime(), job.calls + 1
  if job.calls % 10 == 0 then print(("GameData : %d / %d %s…"):format(job.bought, job.wanted, job.name)) end
end

function ns.bulkBuy(id, wanted)
  if job then return print("GameData : un achat en gros est déjà en cours (/gdata stop pour l'arrêter).") end
  wanted = math.floor(tonumber(wanted) or 0)
  if wanted <= 0 then return end
  if not merchantIndex(id) then return print("GameData : ce marchand ne vend pas cet objet.") end
  job = { id = id, wanted = wanted, bought = 0, calls = 0, name = C_Item.GetItemNameByID(id) or ("objet " .. id) }
  job.ticker = C_Timer.NewTicker(0.25, step)
end

local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("MERCHANT_CLOSED")
f:SetScript("OnEvent", function(_, event)
  if not job then return end
  if event == "MERCHANT_CLOSED" then stop("marchand fermé") else job.waiting = nil end -- sacs à jour : pile suivante
end)

-- Alt + clic sur un article : la boîte « combien ? », avec le maximum que permettent ton or et tes sacs.
StaticPopupDialogs.GAMEDATA_BULKBUY = {
  text = "Combien de %s acheter ?\n(max %d : ton or et la place dans tes sacs)",
  button1 = "Acheter", button2 = "Annuler", hasEditBox = true, timeout = 0, whileDead = false, hideOnEscape = true,
  OnShow = function(self, data)
    local box = self.GetEditBox and self:GetEditBox() or self.editBox
    box:SetText(tostring(data.max))
    box:HighlightText()
  end,
  OnAccept = function(self, data)
    local box = self.GetEditBox and self:GetEditBox() or self.editBox
    ns.bulkBuy(data.id, math.min(data.max, tonumber(box:GetText()) or 0))
  end,
  EditBoxOnEnterPressed = function(box, data)
    local popup = box:GetParent()
    ns.bulkBuy(data.id, math.min(data.max, tonumber(box:GetText()) or 0))
    popup:Hide()
  end,
  EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
}

if MerchantItemButton_OnModifiedClick then
  hooksecurefunc("MerchantItemButton_OnModifiedClick", function(button)
    if not IsAltKeyDown() or (MerchantFrame.selectedTab or 1) ~= 1 then return end
    local index = button:GetID()
    local id, info = GetMerchantItemID(index), C_MerchantFrame.GetItemInfo(index)
    if not (id and info and info.price and info.price > 0) or info.hasExtendedCost then return end
    local lot = math.max(1, info.stackCount or 1)
    local stack = math.max(lot, GetMerchantItemMaxStack(index))
    local max = math.min(math.floor(GetMoney() / (info.price / lot)), ns.freeUnits(id, stack))
    max = math.floor(max / lot) * lot
    if max <= 0 then return print("GameData : pas assez d'or ou de place pour en acheter.") end
    StaticPopup_Show("GAMEDATA_BULKBUY", info.name or C_Item.GetItemNameByID(id), max, { id = id, max = max })
  end)
end
