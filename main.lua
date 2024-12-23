-- https://www.nexusmods.com/morrowind/mods/55629

local isDebugOn = true

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
-- trainer's skill value is 1 temporarily,
-- but should return to its original value later.
local function onTrainingMenuClose()
  if not tes3.player.data.trainedAt then
    return
  end
  if not tes3.player.data.trainedAt[trainerCurrentId] then
    return
  end

  for skillId, skillValue in pairs(tes3.player.data.trainedAt[trainerCurrentId]) do
    log('[TrainersRebalanced] onTrainingMenuClose skillId: %s, skillValue: %s', skillId, skillValue)
    -- restore trainer's original skill value
    tes3.setStatistic({ reference = tes3.getReference(trainerCurrentId), skill = skillId, value = skillValue })
  end
end

--- @param e uiEventEventData
local function uiEventCallback(e)
  if tostring(e.parent) ~= 'UIEXP_MenuTraining_Cancel' then
    return
  end

  onTrainingMenuClose()
end
event.register(tes3.event.uiEvent, uiEventCallback)

-- patch for Right Click Menu Exit, should do the same as uiEventCallback, but right-click doesn't catch it
local function onMouseButtonDown(e)
  if tes3ui.menuMode() then
    if e.button == tes3.worldController.inputController.inputMaps[19].code then
      local menuOnTop = tes3ui.getMenuOnTop()
      if tostring(menuOnTop) == 'MenuServiceTraining' then
        onTrainingMenuClose()
      end
    end
  end
end
event.register("mouseButtonDown", onMouseButtonDown)

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
  log('[TrainersRebalanced][calcTrainingPriceCallback] -----------------------------------')

  trainerCurrent = e.reference
  trainerCurrentMobile = e.mobile
  trainerCurrentId = trainerCurrent.id
  local skillId = e.skillId
  local trainerSkillValueOriginal = trainerCurrentMobile:getSkillValue(skillId)
  local trainerTier = getTrainerTier(trainerSkillValueOriginal)
  trainingIterations = nil
  e.price = e.price * trainerTier
  skillProgressRequirement[skillId] = tes3.mobilePlayer:getSkillProgressRequirement(skillId)

  log('[TrainersRebalanced][calcTrainingPriceCallback] trainerCurrentId: %s', trainerCurrentId)
  log('[TrainersRebalanced][calcTrainingPriceCallback] e.ref: %s, e.basePrice: %s, e.price: %s, e.skillId: %s (%s)', e.reference, e.basePrice, e.price, skillId, skills[skillId])
  log('[TrainersRebalanced][calcTrainingPriceCallback] skillProgressRequirement[skillId]: %s (%s)', skillProgressRequirement[skillId], skills[skillId])

  if (tes3.player.data.trainedAt 
    and tes3.player.data.trainedAt[trainerCurrentId]
    and tes3.player.data.trainedAt[trainerCurrentId][skillId]) then
      -- TODO: this could be moved to skillRaisedCallback to refresh available skills sooner, but it might be confusing for player

      log('[TrainersRebalanced][calcTrainingPriceCallback] ALREADY trained skillId %s at %s, block it', skillId, trainerCurrentId)
      -- TODO: check if resets skill and remove
      log('[TrainersRebalanced][calcTrainingPriceCallback] Unarmored skill BEFORE: %s', trainerCurrentMobile:getSkillValue(tes3.skill['unarmored']))
      log('[TrainersRebalanced][calcTrainingPriceCallback] trainer\'s skill BEFORE: %s', trainerSkillValueOriginal)
      -- decrease current trainer's skill value to 1, to prevent skilling more than once
      tes3.setStatistic({ reference = tes3.getReference(trainerCurrentId), skill = skillId, value = 1 })
      log('[TrainersRebalanced][calcTrainingPriceCallback] trainer\'s skill AFTER: %s', trainerCurrentMobile:getSkillValue(skillId))
    end

  if (not tes3.player.data.trainedAt) then
    tes3.player.data.trainedAt = {}
    log('[TrainersRebalanced][calcTrainingPriceCallback] Mod used for the first time. CREATED tes3.player.data.trainedAt')
  end
end
event.register(tes3.event.calcTrainingPrice, calcTrainingPriceCallback)

--- @param e skillRaisedEventData
local function skillRaisedCallback(e)
  log('[TrainersRebalanced][skillRaisedCallback] -----------------------------------')
  log('[TrainersRebalanced][skillRaisedCallback] e.source: %s', e.source)

  if e.source ~= 'training' and not (e.source == 'progress' and trainingIterations ~= nil) then
    -- bumping skill programatically with mobile:progressSkillToNextLevel is treated as "progress"
    return
  end

  local skillId = e.skill
  local trainerSkillValueOriginal = trainerCurrentMobile:getSkillValue(skillId)
  local trainerTier = getTrainerTier(trainerSkillValueOriginal)

  log('[TrainersRebalanced][skillRaisedCallback] trainingIterations left: %s (of %s)', trainingIterations, trainerTier)
  log('[TrainersRebalanced][skillRaisedCallback] trained at NPC: %s', trainerCurrentId)
  log('[TrainersRebalanced][skillRaisedCallback] trained skill id: %s (%s)', skillId, skills[skillId])
  log('[TrainersRebalanced][skillRaisedCallback] trainerTier: %s', trainerTier)
  log('[TrainersRebalanced][skillRaisedCallback] trainer\'s skill value: %s', trainerSkillValueOriginal)
  log('[TrainersRebalanced][skillRaisedCallback] trained to level: %s', e.level)
  
  if trainingIterations ~= nil and trainingIterations == 1 then
    -- this is executed once per skill train loop, in LAST iteration
    log('[TrainersRebalanced][skillRaisedCallback] trainingIterations finished for %s, reset trainingIterations', skills[skillId])
    trainingIterations = nil

    -- take xp overflow into account!
    -- check if the skill that we're leveling up had any progress, and then add it
    -- current getSkillProgressRequirement is 100% (when on UI it's 0/100), 
    -- so whatever progress was required before training (the old value in skillProgressRequirement[skillId])
    -- needs to be subtracted from getSkillProgressRequirement and the result should be added to current progress 
    -- (for simplicity it assumes progress is linear, but in fact higher levels should have bigger requirements)
    local xpOverflow = tes3.mobilePlayer:getSkillProgressRequirement(skillId) - skillProgressRequirement[skillId]
    log('[TrainersRebalanced][skillRaisedCallback] tes3.mobilePlayer:getSkillProgressRequirement(skillId): %s, skillProgressRequirement[skillId]: %s', xpOverflow, skillProgressRequirement[skillId])
    log('[TrainersRebalanced][skillRaisedCallback] xpOverflow: %s', xpOverflow)
    if not xpOverflow or xpOverflow == 0 then return end
    skillProgressRequirement[skillId] = nil
    tes3.mobilePlayer:exerciseSkill(skillId, xpOverflow)

    return
  end

  if trainingIterations == nil then
    -- this is executed once per skill train loop, in FIRST iteration
    -- training is repeated, once per every trainer tier (max. 5 times)
    trainingIterations = trainerTier

    -- remember that this skill was trained at this NPC
    -- save value as trainer's original skill level, to reset it after closing training window
    if (not tes3.player.data.trainedAt[trainerCurrentId]) then
      tes3.player.data.trainedAt[trainerCurrentId] = {}
      log('[TrainersRebalanced][skillRaisedCallback] trained at %s for the first time, CREATED tes3.player.data.trainedAt[trainerCurrentId]', trainerCurrent)
    end
    log('[TrainersRebalanced][skillRaisedCallback] %s teached %s for the first time, CREATED tes3.player.data.trainedAt[trainerCurrentId][skillId]', trainerCurrent, skills[skillId])
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

  trainingIterations = trainingIterations - 1

  if trainingIterations > 0 then
    -- repeat skillRaisedCallback for every trainingIterations left
    tes3.getPlayerRef().mobile:progressSkillToNextLevel(skillId)
  end
end
event.register(tes3.event.skillRaised, skillRaisedCallback)


local function onInitialized()
  mwse.log('[TrainersRebalanced] Mod initialized.')
end
event.register('initialized', onInitialized)
