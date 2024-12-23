-- https://www.nexusmods.com/morrowind/mods/55629

local isDebugOn = true

-- TODO prefix with G
local trainerCurrent
local trainerCurrentMobile
local trainerCurrentId
local trainingIterations
local skillProgressRequirement = {}

local tierToExperience = {
  [1] = 'modest',
  [2] = 'interesting',
  [3] = 'meaningful',
  [4] = 'significant',
  [5] = 'legendary'
}

local function log(...)
  if not isDebugOn then
    return
  end

  local filteredArgs = {}
  for i = 1, select("#", ...) do -- select("#", ...) gets the total number of arguments
    local v = select(i, ...)  -- Access each argument by its position

    if v == nil then
      v = 'NIL!'
    end

    table.insert(filteredArgs, tostring(v))
  end

  mwse.log(table.unpack(filteredArgs))
end

-- { unarmored: 1 } -> { 1: 'unarmored' }
-- skills[1] = alternative for tes3.getSkillName(1)
local function invertTable(tbl)
  local inverted = {}
  for key, value in pairs(tbl) do
    inverted[value] = key
  end
  return inverted
end
local skills = invertTable(tes3.skill)

-- Restores trainer's original skill value.
-- When training window is opened
-- and training for that NPC's skill disabled, 
-- trainer's skill value is set to 1 temporarily,
-- but should return to its original value later.
local function restoreTrainerSkills()
  if not tes3.player.data.trainedAt then
    return
  end
  if not tes3.player.data.trainedAt[trainerCurrentId] then
    return
  end

  log('[TRU] Restoring trainer\'s skills.')
  for skillId, skillValue in pairs(tes3.player.data.trainedAt[trainerCurrentId]) do
    log('[TRU] skillId: %s (%s), skillValue: %s', skillId, skills[skillId], skillValue)
    tes3.setStatistic({ reference = tes3.getReference(trainerCurrentId), skill = skillId, value = skillValue })
  end
end

-- patch for Right Click Menu Exit, should do the same as uiEventCallback, but right-click doesn't catch it
local function onMouseButtonDown(e)
  if tes3ui.menuMode() then
    if e.button == tes3.worldController.inputController.inputMaps[19].code then
      local menuOnTop = tes3ui.getMenuOnTop()
      if tostring(menuOnTop) == 'MenuServiceTraining' then
        restoreTrainerSkills()
      end
    end
  end
end
event.register("mouseButtonDown", onMouseButtonDown)

--- @param e uiEventEventData
local function uiEventCallback(e)
  mwse.log('parent %s, property %s, source %s', e.parent, e.property, e.source)
  local mouseDown = 4294934580 -- mouseDown, on mouseClick parent and source is nil

  local closeButtons = {
    UIEXP_MenuTraining_Cancel = true,
    MenuDialog_button_bye = true
  }

  if (e.property == mouseDown) and closeButtons[tostring(e.parent)] then
    restoreTrainerSkills()
    return
  end

  if (e.property == mouseDown) and (tostring(e.parent) == 'MenuDialog_service_training') then
    -- 'Training' in dialogue menu is clicked
    npcRef = tes3ui.getServiceActor().reference
    log('[TRU][uiEventCallback] training window is going to open for NPC: %s', tes3ui.getServiceActor().reference)
    hideTrainerSkills(npcRef)
  end
end
event.register(tes3.event.uiEvent, uiEventCallback)

-- TODO: add requirement for ui expansion
-- TODO: test on master trainers

-- local function onDialogueStart(e)
--   npcRef = e.element:getPropertyObject("PartHyperText_actor").reference
--   if npcRef.object.objectType ~= tes3.objectType.npc then
--     npcRef = nil
--     return
--   end
--   timer.delayOneFrame(function()
--     log('[TRU] dialogue window OR training window opened')
--     log('[TRU][hideTrainerSkills] Unarmored skill (test) BEFORE: %s', npcRef.mobile:getSkillValue(tes3.skill['unarmored']))
--     tes3.messageBox('NPC unarmored skill value %s', npcRef.mobile:getSkillValue(tes3.skill['unarmored']))
--     -- should NOT be 1 after training
--     -- hideTrainerSkills(npcRef)
--   end)
-- end
-- event.register("uiActivated", onDialogueStart, {filter = "MenuDialog"})
-- this is actually not needed anymore, only for tests

function hideTrainerSkills(npcRef)
  log('[TRU][hideTrainerSkills] -----------------------------------')

  if (not tes3.player.data.trainedAt) then
    tes3.player.data.trainedAt = {}
    log('[TRU][hideTrainerSkills] Mod used for the first time. CREATED tes3.player.data.trainedAt')
  end

  trainerCurrent = npcRef
  trainerCurrentId = trainerCurrent.id
  trainerCurrentMobile = npcRef.mobile
  mwse.log('[TRU][hideTrainerSkills] trainerCurrent: %s, trainerCurrentMobile: %s, trainerCurrentId: %s', trainerCurrent, trainerCurrentMobile, trainerCurrentId)

  if (tes3.player.data.trainedAt 
  and tes3.player.data.trainedAt[trainerCurrentId]) then
    -- for each already trained skill in tes3.player.data.trainedAt[trainerCurrentId]
    -- decrease current trainer's skill value to 1, to prevent skilling more than once
    -- TODO: this could be copied to skillRaisedCallback to refresh available skills sooner, but it might be confusing for player
    for skillId, skillValue in pairs(tes3.player.data.trainedAt[trainerCurrentId]) do
      log('[TRU][hideTrainerSkills] ALREADY trained skillId %s (%s) at %s, block it', skillId, skills[skillId], trainerCurrentId)
      log('[TRU][hideTrainerSkills] trainer\'s skill BEFORE: %s', trainerSkillValueOriginal)
      tes3.setStatistic({ reference = tes3.getReference(trainerCurrentId), skill = skillId, value = 1 })
      log('[TRU][hideTrainerSkills] trainer\'s skill AFTER: %s', trainerCurrentMobile:getSkillValue(skillId))
    end
  end
end

function bankersRound(value)
  if value % 1 == 0.5 then
    return math.floor(value)
  else
    return math.floor(value + 0.5)
  end
end

local function getTrainerTier(trainerSkillValue)
  local trainerTier
  if trainerSkillValue < 20 then
    -- skill value 1-30
    trainerTier = 1
  else
    -- skill 31-100 = tier 2-5 (master trainer = 5)
    trainerTier = bankersRound(trainerSkillValue / 20)
  end
  return trainerTier
end

--- @param e calcTrainingPriceEventData
local function calcTrainingPriceCallback(e)
  log('[TRU][calcTrainingPriceCallback] -----------------------------------')

  trainerCurrent = e.reference
  trainerCurrentMobile = e.mobile
  local skillId = e.skillId
  local trainerSkillValueOriginal = trainerCurrentMobile:getSkillValue(skillId)
  local trainerTier = getTrainerTier(trainerSkillValueOriginal)
  trainingIterations = nil
  e.price = e.price * trainerTier
  skillProgressRequirement[skillId] = tes3.mobilePlayer:getSkillProgressRequirement(skillId)

  log('[TRU][calcTrainingPriceCallback] trainerCurrent: %s', trainerCurrent)
  log('[TRU][calcTrainingPriceCallback] e.ref: %s, e.basePrice: %s, e.price: %s, e.skillId: %s (%s)', e.reference, e.basePrice, e.price, skillId, skills[skillId])
  log('[TRU][calcTrainingPriceCallback] skillProgressRequirement[skillId]: %s (%s)', skillProgressRequirement[skillId], skills[skillId])
end
event.register(tes3.event.calcTrainingPrice, calcTrainingPriceCallback)

--- @param e skillRaisedEventData
local function skillRaisedCallback(e)
  log('[TRU][skillRaisedCallback] -----------------------------------')
  log('[TRU][skillRaisedCallback] e.source: %s', e.source)

  if e.source ~= 'training' and not (e.source == 'progress' and trainingIterations ~= nil) then
    -- bumping skill programatically with mobile:progressSkillToNextLevel is treated as "progress"
    return
  end

  local skillId = e.skill
  local trainerSkillValueOriginal = trainerCurrentMobile:getSkillValue(skillId)
  local trainerTier = getTrainerTier(trainerSkillValueOriginal)

  log('[TRU][skillRaisedCallback] trainingIterations left: %s (of %s)', trainingIterations, trainerTier)
  log('[TRU][skillRaisedCallback] trained at NPC: %s', trainerCurrentId)
  log('[TRU][skillRaisedCallback] trained skill id: %s (%s)', skillId, skills[skillId])
  log('[TRU][skillRaisedCallback] trainerTier: %s', trainerTier)
  log('[TRU][skillRaisedCallback] trainer\'s skill value: %s', trainerSkillValueOriginal)
  log('[TRU][skillRaisedCallback] trained to level: %s', e.level)  

  if trainingIterations == nil then
    -- this is executed once per skill train loop, in FIRST iteration
    -- training is repeated, once per every trainer tier (max. 5 times)
    trainingIterations = trainerTier

    -- remember that this skill was trained at this NPC
    -- save value as trainer's original skill level, to reset it after closing training window
    if (not tes3.player.data.trainedAt[trainerCurrentId]) then
      tes3.player.data.trainedAt[trainerCurrentId] = {}
      log('[TRU][skillRaisedCallback] trained at %s for the first time, CREATED tes3.player.data.trainedAt[trainerCurrentId]', trainerCurrent)
    end
    log('[TRU][skillRaisedCallback] %s teached %s for the first time, CREATED tes3.player.data.trainedAt[trainerCurrentId][skillId]', trainerCurrent, skills[skillId])
    tes3.player.data.trainedAt[trainerCurrentId][skillId] = trainerCurrentMobile:getSkillValue(skillId)

    -- move to last iteration?
    tes3.messageBox({
      message = string.format(
        'The training has payed off. %s has shared their %s experience (%s) about %s with you, and you\'ve improved from %s to %s. There is nothing more %s can teach you about %s. Take a break, ask about something else, or find other teacher.', 
        trainerCurrentMobile.object.name,
        tierToExperience[trainerTier],
        trainerSkillValueOriginal,
        skills[skillId],
        e.level-1, -- PC skill before training
        e.level-1+trainingIterations, -- PC skill after training
        trainerCurrentMobile.object.name,
        skills[skillId]
        ),
      buttons = { 'OK' }
    })
  end

  if trainingIterations ~= nil and trainingIterations == 1 then
    -- this is executed once per skill train loop, in LAST iteration
    log('[TRU][skillRaisedCallback] trainingIterations finished for %s, reset trainingIterations', skills[skillId])
    trainingIterations = nil
    hideTrainerSkills(trainerCurrent) -- hide trained skill before training window reopens

    -- take xp overflow into account!
    -- check if the skill that we're leveling up had any progress, and then add it
    -- current getSkillProgressRequirement is 100% (when on UI it's 0/100), 
    -- so whatever progress was required before training (the old value in skillProgressRequirement[skillId])
    -- needs to be subtracted from getSkillProgressRequirement and the result should be added to current progress 
    -- (for simplicity it assumes progress is linear, but in fact higher levels should have bigger requirements)
    local xpOverflow = tes3.mobilePlayer:getSkillProgressRequirement(skillId) - skillProgressRequirement[skillId]
    log('[TRU][skillRaisedCallback] tes3.mobilePlayer:getSkillProgressRequirement(skillId): %s, skillProgressRequirement[skillId]: %s', xpOverflow, skillProgressRequirement[skillId])
    log('[TRU][skillRaisedCallback] xpOverflow: %s', xpOverflow)
    if not xpOverflow or xpOverflow == 0 then return end
    skillProgressRequirement[skillId] = nil
    tes3.mobilePlayer:exerciseSkill(skillId, xpOverflow)

    return
  end

  trainingIterations = trainingIterations - 1
  if trainingIterations > 0 then
    -- repeat skillRaisedCallback for every trainingIterations left
    tes3.getPlayerRef().mobile:progressSkillToNextLevel(skillId)
  end
end
event.register(tes3.event.skillRaised, skillRaisedCallback)

local function onInitialized()
  mwse.log('[TRU] Mod initialized.')

  if isDebugOn then tes3.messageBox({ message = '[TRU] Mod initialized.', duration = 20 }) end
end
event.register('initialized', onInitialized)
