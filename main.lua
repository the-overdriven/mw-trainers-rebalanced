local debug = true
local trainerCurrent
local trainerCurrentMobile
local trainerCurrentId
local trainingIterations

local tierToExperience = {
  [1] = 'modest',
  [2] = 'interesting',
  [3] = 'meaningful',
  [4] = 'significant',
  [5] = 'legendary'
}

local function log(...)
  if not debug then
    return
  end

  local args = {...}

  local filteredArgs = {}
  for i, v in ipairs(args) do
    if v == nil then
        table.insert(filteredArgs, 'nil')
    end
  end

  mwse.log(table.unpack(filteredArgs))
end

-- { foo: 1 } -> { 1: 'foo' }
local function invertTable(tbl)
  local inverted = {}
  for key, value in pairs(tbl) do
    inverted[value] = key
  end
  return inverted
end
local skills = invertTable(tes3.skill)

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
  -- log('[TrainersRebalanced] tes3.event.uiEvent e.parent %s', e.parent)
  -- log('[TrainersRebalanced] tes3.event.uiEvent e.source %s', e.source)
  -- log('[TrainersRebalanced] tes3.event.uiEvent e.property %s', e.property)

  if tostring(e.parent) ~= 'UIEXP_MenuTraining_Cancel' then
    return
  end

  -- onTrainingMenuClose()
end
event.register(tes3.event.uiEvent, uiEventCallback)


-- patch for Right Click Menu Exit
local function onMouseButtonDown(e)
  if tes3ui.menuMode() then
      if e.button == tes3.worldController.inputController.inputMaps[19].code then
        -- closeMenu()
        local menuOnTop = tes3ui.getMenuOnTop()
        if tostring(menuOnTop) == 'MenuServiceTraining' then
          -- onTrainingMenuClose()
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

  log('[TrainersRebalanced][calcTrainingPriceCallback] trainerCurrentId: %s', trainerCurrentId)
  log('[TrainersRebalanced][calcTrainingPriceCallback] e.ref: %s, e.basePrice: %s, e.price: %s, e.skillId: %s (%s)', e.reference, e.basePrice, e.price, skillId, skills[skillId])

  if (tes3.player.data.trainedAt 
    and tes3.player.data.trainedAt[trainerCurrentId]
    and tes3.player.data.trainedAt[trainerCurrentId][skillId]) then
      log('[TrainersRebalanced][calcTrainingPriceCallback] ALREADY trained skillId %s at %s, block it', skillId, trainerCurrentId)

      log('[TrainersRebalanced][calcTrainingPriceCallback] Unarmored skill BEFORE: %s', trainerCurrentMobile:getSkillValue(tes3.skill['unarmored']))
      log('[TrainersRebalanced][calcTrainingPriceCallback] trainer\'s skill BEFORE: %s', trainerSkillValueOriginal)
      -- decrease current trainer's skill value to 1, to prevent skilling more than once
      tes3.setStatistic({ reference = tes3.getReference(trainerCurrentId), skill = skillId, value = 1 })
      log('[TrainersRebalanced][calcTrainingPriceCallback] trainer\'s skill AFTER: %s', trainerCurrentMobile:getSkillValue(skillId))
    end

  if (not tes3.player.data.trainedAt) then
    tes3.player.data.trainedAt = {}
    log('[TrainersRebalanced][calcTrainingPriceCallback] created tes3.player.data.trainedAt for the first time')
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

  log('[TrainersRebalanced][skillRaisedCallback] trainingIterations left: %s', trainingIterations)
  log('[TrainersRebalanced][skillRaisedCallback] trained at NPC: %s', trainerCurrentId)
  log('[TrainersRebalanced][skillRaisedCallback] trained skill id: %s (%s)', skillId, skills[skillId])
  log('[TrainersRebalanced][skillRaisedCallback] trainerTier: %s', trainerTier)
  log('[TrainersRebalanced][skillRaisedCallback] trainer\'s skill value: %s', trainerSkillValueOriginal)
  log('[TrainersRebalanced][skillRaisedCallback] trained to level: %s', e.level)
  
  if trainingIterations ~= nil and trainingIterations == 1 then
    -- reset
    log('[TrainersRebalanced][skillRaisedCallback] trainingIterations finished, reset trainingIterations')
    trainingIterations = nil
    return
  end

  if trainingIterations == nil then
    -- this is executed once per skill train loop, in first iteration
    -- training is repeated, once per every trainer tier (max. 5 times)
    trainingIterations = trainerTier

    -- remember that this skill was trained at this NPC
    -- save value as trainer's original skill level, to reset it after closing training window
    if (not tes3.player.data.trainedAt[trainerCurrentId]) then
      tes3.player.data.trainedAt[trainerCurrentId] = {}
      log('[TrainersRebalanced][skillRaisedCallback] trained at %s for the first time, created tes3.player.data.trainedAt[trainerCurrentId]', trainerCurrent)
    end
    log('[TrainersRebalanced][skillRaisedCallback] %s teached %s for the first time, created tes3.player.data.trainedAt[trainerCurrentId][skillId]', trainerCurrent, skills[skillId])
    tes3.player.data.trainedAt[trainerCurrentId][skillId] = trainerCurrentMobile:getSkillValue(skillId)

    -- move to last iteration?
    tes3.messageBox({
      message = string.format(
        'The training has payed off. %s has shared their %s experience (%s) about %s with you, and you\'ve improved from %s to %s. There is nothing more %s can teach you about %s. Take a break, ask about something else, or find other teacher.', 
        trainerCurrentMobile.object.name,
        tierToExperience[trainerTier],
        trainerSkillValueOriginal,
        skills[skillId],
        e.level-1,
        e.level+trainingIterations,
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
  log("[TrainersRebalanced] Mod initialized.")
end
event.register("initialized", onInitialized)
