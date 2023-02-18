local table_insert = table.insert
local table_RemoveByValue = table.RemoveByValue
local ipairs = ipairs
local table_Empty = table.Empty
local RandomPairs = RandomPairs
local random = math.random
local Rand = math.Rand
local CurTime = CurTime

local function Initialize( self, wepent )

    self.lc_group = {} -- A table holding every other player in our conversation
    self.lc_canspeak = false -- If it's our turn to speak in a conversation
    self.lc_maxspeaktimes = 0 -- The maximum times we can talk during a conversation before we stop
    self.lc_currentspeaktimes = 0 -- How many times we've spoken during the conversations
    self.lc_respondent = false -- Are we supposed to respond to a question?
    self.lc_movementtbl = {}

    -- Returns if we are in a conversation with this entity
    function self:IsInConvoWith( ent )
        for k, v in ipairs( self.lc_group ) do
            if v == ent then return true end
        end
        return false
    end

    -- Conversation state
    function self:Conversation()
        if #self.lc_group == 0 then self:ExitConversation() return end
        if self.lc_currentspeaktimes >= self.lc_maxspeaktimes then self:ExitConversation() return end

        -- Don't play any idle sounds
        self.l_nextidlesound = math.huge 

        local partner = self.lc_group[ random( #self.lc_group ) ]

        -- Look at the person speaking
        if !self:HookExists( "LambdaConvoOnSpeak", "lookatspeaker" ) then
            self:Hook( "LambdaConvoOnSpeak", "lookatspeaker", function( lambda )
                if #self.lc_group == 0 then return "end" end
                if lambda == self or !self:IsInConvoWith( lambda ) then return end
                self:LookTo( lambda, Rand( 0, 1 ) )
            end )
        end

        if !self:HookExists( "PlayerSay", "endtext" ) then
            self:Hook( "PlayerSay", "endtext", function( ply )
                if #self.lc_group == 0 then return "end" end
                if !self:IsInConvoWith( ply ) then return end
                if ply.lc_canspeak then
                    ply.lc_canspeak = false 

                    if random( 1, 2 ) == 1 then
                        partner = self.lc_group[ random( #self.lc_group ) ] 
                        partner.lc_canspeak = true  
                    else
                        self.lc_canspeak = true
                    end
                end
            end )
        end

        if !self:HookExists( "LambdaOnRealPlayerEndVoice", "endvoice" ) then
            self:Hook( "LambdaOnRealPlayerEndVoice", "endvoice", function( ply )
                if #self.lc_group == 0 then return "end" end
                if !self:IsInConvoWith( ply ) then return end
                if ply.lc_canspeak then
                    ply.lc_canspeak = false 

                    if random( 1, 2 ) == 1 then
                        partner = self.lc_group[ random( #self.lc_group ) ] 
                        partner.lc_canspeak = true  
                    else
                        self.lc_canspeak = true
                    end
                end

            end )
        end

        
        if self:GetRangeSquaredTo( partner ) > ( 150 * 150 ) then

            self.lc_movementtbl.callback = function() 
                if IsValid( partner ) and self:GetRangeSquaredTo( partner ) <= ( 150 * 150 ) then
                    self:CancelMovement()
                end
            end

            self:MoveToPos( partner:GetPos(), self.lc_movementtbl )
        end

        -- Wait until it is our turn to speak or if our group is gone
        while !self.lc_canspeak and #self.lc_group != 0 do coroutine.yield() end
        if self.lc_group == 0 then return end
        
        hook.Run( "LambdaConvoOnSpeak", self )

        -- Not answering a question, therefor we must ask one.
        -- Small chance that we ask a new one.
        if !self.lc_respondent or random( 100 ) <= 1 then
            self:PlaySoundFile( self:GetVoiceLine( "conquestion" ), true )

            self.lc_respondent = true -- We set ourself as a respondent to avoid making us the only inquirer in a one on one convo
            for k, v in ipairs( self.lc_group ) do
                v.lc_respondent = true -- Asked a question, the rest must answer.
            end

        -- We are answering a question
        else
            self:PlaySoundFile( self:GetVoiceLine( "conrespond" ), true )
            
            self.lc_respondent = false -- Provided a response to the question. If we go back to us, we will ask a question.
        end
        
        self.lc_canspeak = false
        self.lc_currentspeaktimes = self.lc_currentspeaktimes + 1

        -- Wait until we stop speaking or if our group is gone
        while self:IsSpeaking() and #self.lc_group != 0 do coroutine.yield() end
        if #self.lc_group == 0 then return end

        coroutine.wait( 0.3 )
        if #self.lc_group == 0 then self:ExitConversation() return end
        -- Time for someone else to speak
        partner = self.lc_group[ random( #self.lc_group ) ]

        partner.lc_canspeak = true

        -- Just so we don't get stuck waiting for a response
        if partner:IsPlayer() then 
            hook.Run( "LambdaConvoOnSpeak", partner ) 
            self:NamedTimer( "convotimeout", 10, 1, function()
                if partner.lc_canspeak then 
                    partner.lc_canspeak = false  

                    if random( 1, 2 ) == 1 then
                        partner = self.lc_group[ random( #self.lc_group ) ] 
                        if IsValid( partner ) then partner.lc_canspeak = true end
                    else
                        self.lc_canspeak = true
                    end
                end  
            end)
        end 

    end


    -- Leave the conversation we are in
    function self:ExitConversation()
        self.l_nextidlesound = CurTime() + 5
        self.lc_respondent = false
        self:LookTo()
        self:SetState( "Idle" )
        self:RemoveHook( "LambdaConvoOnSpeak", "lookatspeaker" )
        self:RemoveHook( "LambdaOnRealPlayerEndVoice", "endvoice" )
        for k, v in ipairs( self.lc_group ) do
            table_RemoveByValue( v.lc_group, self )
        end
        table_Empty( self.lc_group )
    end

    function self:StartConversation( ent )
        if !IsValid( ent ) then return end
        if #self.lc_group == 0 and ( !ent.lc_group or #ent.lc_group == 0 ) then
            ent.lc_group = ent.lc_group or {}

            table_insert( self.lc_group, ent )
            table_insert( ent.lc_group, self )

            self.lc_canspeak = true
            self.lc_maxspeaktimes = random( 3, 20 )
            self.lc_currentspeaktimes = 0

            ent.lc_canspeak = false
            ent.lc_maxspeaktimes = random( 3, 20 )
            ent.lc_currentspeaktimes = 0


            self:LookTo( ent )
            if ent.IsLambdaPlayer then ent:LookTo( self ) end
            self:SetState( "Conversation" )
            self:CancelMovement()
            if ent.IsLambdaPlayer then
                ent:SetState( "Conversation" )
                ent:CancelMovement()
            end

        elseif #self.lc_group == 0 and ent.lc_group and #ent.lc_group != 0 then

            for k, v in ipairs( ent.lc_group ) do
                table_insert( self.lc_group, v )
                table_insert( v.lc_group, self )
            end

            table_insert( self.lc_group, ent )
            table_insert( ent.lc_group, self )

            self.lc_canspeak = false
            self.lc_maxspeaktimes = random( 3, 20 )
            self.lc_currentspeaktimes = 0

            self:LookTo( ent )
            self:SetState( "Conversation" )
            self:CancelMovement()

        end
    end

end

local function OnRemove( self )
    local partner = self.lc_group[ random( #self.lc_group ) ]
    if IsValid( partner ) and (self:IsSpeaking() or self.lc_canspeak) then partner.lc_canspeak = true end
    
    for k, v in ipairs( self.lc_group ) do
        if !v.lc_group then continue end
        table_RemoveByValue( v.lc_group, self )
    end
end

local function Think( self )
    if #self.lc_group != 0 and self:GetState() != "Conversation" then
        self.l_nextidlesound = CurTime() + 5
        self:RemoveHook( "LambdaConvoOnSpeak", "lookatspeaker" )
        self:RemoveHook( "LambdaOnRealPlayerEndVoice", "endvoice" )

        local partner = self.lc_group[ random( #self.lc_group ) ]
        if IsValid( partner ) and self.lc_canspeak then partner.lc_canspeak = true end
        
        for k, v in ipairs( self.lc_group ) do
            if !v.lc_group then continue end
            table_RemoveByValue( v.lc_group, self )
        end

        table_Empty( self.lc_group )
    end
end

local function LookConversation( self )
    if random( 1, 2 ) != 1 then return end
    if self:GetState() != "Idle" then return end
    local nearby = self:FindInSphere( nil, 2000, function( ent ) return ent != self and ( ent.IsLambdaPlayer and ent:GetState() == "Idle" or ent:IsPlayer() and !GetConVar( "ai_ignoreplayers" ):GetBool() ) and self:CanSee( ent ) end )

    for k, ply in RandomPairs( nearby ) do
        self:StartConversation( ply )
        break
    end
end

AddUActionToLambdaUA( LookConversation )

LambdaRegisterVoiceType( "conquestion", "randomengine", "These are voice lines that play when a Lambda Player asks a question in a conversation." )
LambdaRegisterVoiceType( "conrespond", "randomengine", "These are voice lines that play when a Lambda Player answer in a conversation." )


-- I'm lazy lol
local prefix = "lambdaconversationmodule_"

hook.Add( "LambdaOnKilled", prefix .. "onkilled", OnRemove )
hook.Add( "LambdaOnThink", prefix .. "think", Think )
hook.Add( "LambdaOnRemove", prefix .. "remove", OnRemove )
hook.Add( "LambdaOnInitialize", prefix .. "init", Initialize )