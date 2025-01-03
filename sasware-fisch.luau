--!nolint BuiltinGlobalWrite

local Success, Error = pcall(function()
	Start = os.clock()
	NO_HOOKING = false

	local Version = 0.9
	local SubVersion = "indev"
	local Debugging = true
	local Title = "Sasware"

	local HttpService = game:GetService("HttpService")
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	if ReplicatedStorage:WaitForChild("Link", 1) then
		ReplicatedStorage = ReplicatedStorage:WaitForChild("Link") -- the devs are tweaking
	end

	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local VirtualInputManager = game:GetService("VirtualInputManager") -- detected ik
	local VirtualUser = game:GetService("VirtualUser")
	local StarterGui = game:GetService("StarterGui")
	local GuiService = game:GetService("GuiService")
	local CollectionService = game:GetService("CollectionService")
	local UserInputService = game:GetService("UserInputService")
	local Lighting = game:GetService("Lighting")
	local VeryImportantPart = Instance.new("Part") -- fake zone for tricking temperature/oxygen scripts
	-- 													it's scuffed but works on literally any exec

	local Toasts = loadstring(game:HttpGet("https://raw.githubusercontent.com/centerepic/sasware-fisch/refs/heads/main/toasts.lua"))()

	do
		local prio = Instance.new("IntValue", VeryImportantPart)
		prio.Name = "priority"
		prio.Value = 999
		local name = Instance.new("StringValue", VeryImportantPart)
		name.Name = "zonename"
		name.Value = "sasware"
	end
	
	local Camera = workspace.CurrentCamera

	local ZoneFishOrigin = nil

	local PreAutoloadConfig = true

	local State = {
		GettingMeteor = false,
		OwnedBoats = {},
	}

	local GlobalStorage = {
		PeakZones = {
			["Overgrowth Caves"] = true,
			["Frigid Cavern"] = true,
			["Cryogenic Canal"] = true,
			["Glacial Grotto"] = true
		}
	}

	-- Game instance paths
	local LocalPlayer = Players.LocalPlayer
	local Unloaded = false
	local CurrentTool: Tool?

	-- Test if hooking is enabled
	if not (hookfunction and hookmetamethod) then
		hookfunction = function(...) end
		hookmetamethod = function(...) end
		NO_HOOKING = true
	end

	if not getconnections then
		getconnections = function(...) end
	end

	if not setthreadidentity then
		setthreadidentity = function(...) end -- i hate you solara
	end

	if getgenv().sasware_fisch_unload then
		pcall(getgenv().sasware_fisch_unload)
	end

	local function Unimplemented()
		return warn("This feature is not implemented yet")
	end

	local function dbgprint(...)
		if Debugging then
			print("[Debugging]", ...)
		end
	end

	local function dbgwarn(...)
		if Debugging then
			warn("[Debugging]", ...)
		end
	end

	--[[
		Recursively waits for instances to exist from a root instance.
	]]
	--
	local function WaitForTable(Root: Instance, InstancePath: { string }, Timeout: number?)
		local Instance = Root
		for i, v in pairs(InstancePath) do
			Instance = Instance:WaitForChild(v, Timeout)
		end
		return Instance
	end

	local function EnsureInstance(Instance: Instance?): boolean
		return (Instance and Instance:IsDescendantOf(game))
	end

	local function _round(num, numDecimalPlaces): number
		local mult = 10 ^ (numDecimalPlaces or 0)
		return math.floor(num * mult + 0.5) / mult
	end

	local Configuration = {
		CheckSafeRange = 50,
	}

	local Remotes = {
		ReelFinished = ReplicatedStorage.events:WaitForChild("reelfinished"),
	}

	local Interface = {
		FishRadar = ReplicatedStorage.resources.items.items["Fish Radar"]["Fish Radar"],
		TeleportSpots = WaitForTable(workspace, { "world", "spawns", "TpSpots" }),
		Inventory = WaitForTable(LocalPlayer.PlayerGui, { "hud", "safezone", "backpack" }),
		MeteorItems = workspace:WaitForChild("MeteorItems"),
		PlayerData = ReplicatedStorage:WaitForChild("playerstats"):WaitForChild(LocalPlayer.Name),
		NPCs = workspace:WaitForChild("world"):WaitForChild("npcs"),
		BoatModels = WaitForTable(ReplicatedStorage, { "resources", "replicated", "instances", "vessels" }),
		Active = workspace:WaitForChild("active"),
		ActiveBoats = workspace:WaitForChild("active"):WaitForChild("boats"),
	}

	local Collection = {}
	local OnUnload = Instance.new("BindableEvent")
	local function Collect(Item: RBXScriptConnection | thread)
		table.insert(Collection, Item)
	end

	local Repository = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/refs/heads/main/"
	local Library = loadstring(game:HttpGet(Repository .. "Library.lua"))()
	local ThemeManager = loadstring(game:HttpGet(Repository .. "addons/ThemeManager.lua"))()
	local SaveManager = loadstring(game:HttpGet(Repository .. "addons/SaveManager.lua"))()
	local VelocityFly =
		loadstring(game:HttpGet("https://raw.githubusercontent.com/centerepic/VelocityFly/main/VelocityFly.lua"))()

	local UI = {
		Library = Library,
		Options = getgenv().Options,
		Toggles = getgenv().Toggles,
	}

	local function GetToggleValue(Name: string): boolean?
		local Toggle = UI.Toggles[Name]

		if not Toggle then
			dbgwarn("Toggle not found:", Name)
			return nil
		else
			return Toggle.Value
		end
	end

	local function GetOptionValue(Name: string)
		local Option = UI.Options[Name]

		if not Option then
			dbgwarn("Option not found:", Name)
			return nil
		else
			return Option.Value
		end
	end

	local Utils = {}
	do

		function Utils.CountInstances(Parent : Instance, Name : string) : number
			local Count = 0
			for _, Instance in next, Parent:GetChildren() do
				if Instance.Name == Name then
					Count += 1
				end
			end
			return Count
		end

		function Utils:BreakVelocity()
			if LocalPlayer.Character then
				task.spawn(function()
					for i = 20, 1, -1 do
						RunService.Heartbeat:Wait()
						for _, Part in next, LocalPlayer.Character:GetDescendants() do
							if Part:IsA("BasePart") then
								Part.Velocity = Vector3.new(0, 0, 0)
								Part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
							end
						end
					end
				end)
			end
		end

		function Utils.ToggleLocationCC(Value: boolean)
			local LocationCC = Lighting:FindFirstChild("location")

			if LocationCC then
				LocationCC.Enabled = Value
			end
		end

		function Utils.GameNotify(Message: string)
			ReplicatedStorage.events.anno_localthoughtbig:Fire(Message, nil, nil, nil, "Exotic")
		end

		function Utils.GetCharacters()
			local Characters = {}

			for _, Player: Player in next, Players:GetPlayers() do
				if Player.Character then
					table.insert(Characters, Player.Character)
				end
			end

			return Characters
		end

		function Utils.Character()
			return LocalPlayer.Character
		end

		function Utils.Humanoid(): Humanoid?
			local Character = Utils.Character()

			if Character then
				return Character:FindFirstChildOfClass("Humanoid")
			end

			return nil
		end

		function Utils.CastTo(A: Vector3, B: Vector3, Params: RaycastParams): RaycastResult?
			local Direction = (B - A)
			return workspace:Raycast(A, Direction, Params)
		end

		--[[
		Checks if there are any characters within range of a position.
		It raycasts from the position to the character's head, alongside checking a sphere of half the range around the position.
	]]
		--
		function Utils.SafePosition(Position: Vector3, Range: number)
			local Characters = Utils.GetCharacters()
			local RayParams = RaycastParams.new()
			RayParams.FilterType = Enum.RaycastFilterType.Exclude
			RayParams.RespectCanCollide = true
			RayParams.FilterDescendantsInstances = Characters

			for _, Character in next, Characters do
				local Head = Character:FindFirstChild("Head")
				local Pivot = Character:GetPivot()

				if Head then
					local Raycast = Utils.CastTo(Position, Head.Position, RayParams)

					if Raycast then
						return false
					end
				end

				if Pivot then
					local Distance = (Position - Pivot.Position).Magnitude * 0.5

					if Distance <= Range then
						return false
					end
				end
			end

			return true
		end

		function Utils.TP(Target: Vector3 | CFrame | PVInstance, CheckSafe: boolean?): boolean
			local Pivot: CFrame

			if typeof(Target) == "CFrame" then
				Pivot = Target
			elseif typeof(Target) == "Vector3" then
				Pivot = CFrame.new(Target)
			elseif typeof(Target) == "PVInstance" then
				Pivot = Target:GetPivot()
			elseif typeof(Target) == "BasePart" then
				Pivot = Target:GetPivot()
			elseif typeof(Target) == "Model" then
				Pivot = Target:GetPivot()
			end

			if CheckSafe then
				if not Utils.SafePosition(Pivot.Position, Configuration.CheckSafeRange) then
					return false
				end
			end

			local Character = Utils.Character()
			if Character then
				Character:PivotTo(Pivot)
				return true
			end

			return false
		end

		function Utils.EliminateVelocity(Model: Model): nil
			for _, Part in next, Model:GetDescendants() do
				if Part:IsA("BasePart") then
					Part.Velocity = Vector3.new(0, 0, 0)
					Part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
				end
			end
			return nil
		end

		function Utils.GenericToast(Duration: number, Message: string, CustomTitle: string?)
			local MessageTitle = CustomTitle or Title

			Toasts.CreateToast(
				HttpService:GenerateGUID(false),
				MessageTitle,
				Message,
				"rbxassetid://18259985431",
				Duration
			)
		end

		function Utils.GetUsernameMatch(PartialName: string): Player?
			local BestMatch = nil
			local BestMatchLength = 0

			for _, Player in next, Players:GetPlayers() do
				if string.find(Player.Name:lower(), PartialName:lower()) then
					if #Player.Name > BestMatchLength then
						BestMatch = Player
						BestMatchLength = #Player.Name
					end
				end
			end

			return BestMatch
		end

		function Utils.CharacterChildAdded(Child: Instance)
			if Child:IsA("Tool") then
				CurrentTool = Child

				if GetToggleValue("ServerStresser") then
					
					local FishModel = Child:WaitForChild("Fish", 1)

					if FishModel then
						FishModel:Destroy()
					end

					task.delay(0.5, function()
						for i,v in next, Child:GetDescendants() do
							if v:IsA("BasePart") then
								v.Anchored = true
							end
						end
					end)

				end

			elseif Child:IsA("Humanoid") then
				Collect(Child.StateChanged:Connect(function()
					if GetToggleValue("ZoneFish") then
						Child:ChangeState(Enum.HumanoidStateType.Running)
					end
				end))
				Collect(Child.Died:Once(function()
					UI.Toggles.ZoneFish:SetValue(false)
				end))
			end
		end

		function Utils.CharacterChildRemoved(Child: Instance)
			if Child:IsA("Tool") then
				CurrentTool = nil
			end
		end

		function Utils.CharacterAdded(Character: Model)
			for _, Child in next, Character:GetChildren() do
				Utils.CharacterChildAdded(Child)
			end

			Collect(Character.ChildAdded:Connect(Utils.CharacterChildAdded))
			Collect(Character.ChildRemoved:Connect(Utils.CharacterChildRemoved))

			local Zone = Character:WaitForChild("zone", 1) :: ObjectValue

			if Zone then
				Collect(RunService.RenderStepped:Connect(function()
					if GetToggleValue("DisablePeakEffects") then
						Zone.Value = VeryImportantPart
					end
				end))
			end
		end

		function Utils.Capitalize(String: string): string
			return string.upper(string.sub(String, 1, 1)) .. string.sub(String, 2)
		end

		function Utils.GetNPC(Type: string, Single: boolean?): Model | { Model } | nil
			local function GetNPCType(NPC: Model) -- i hate this function so much
				local NPCType = "Unknown"

				if NPC:FindFirstChild("shipwright") then
					NPCType = "Shipwright"
				elseif NPC:FindFirstChild("merchant") then
					NPCType = "Merchant"
				elseif NPC:FindFirstChild("angler") then
					NPCType = "Angler"
				end

				return NPCType
			end

			local NPCs = Interface.NPCs:GetChildren()
			local Results = {}

			for _, Character in next, NPCs do
				local NPCType = GetNPCType(Character)

				if NPCType == Type then
					if Single then
						return Character
					else
						table.insert(Results, Character)
					end
				end
			end

			return nil
		end

		function Utils.BoatsChanged()
			local Boats = Interface.PlayerData.Boats:GetChildren()

			State.OwnedBoats = {}

			for _, Boat in next, Boats do
				table.insert(State.OwnedBoats, Boat.Name)
			end

			UI.Options.BoatSpawnDropdown:SetValues(State.OwnedBoats)
		end

		function Utils.UpdateShopDropdown()
			local Items = workspace:WaitForChild("world"):WaitForChild("interactables"):GetChildren()

			local Values = {}

			for _, Item in next, Items do
				table.insert(Values, Item.Name)
			end

			UI.Options.RemoteShopDropdown:SetValues(Values)
		end

	end

	local TeleportLocations = {}
	local TeleportLocations_DropDownValues = {}

	for _, Location in next, Interface.TeleportSpots:GetChildren() do
		TeleportLocations[Utils.Capitalize(Location.Name)] = Location.Position + Vector3.new(0, 6, 0)
	end

	for Name, Position in next, TeleportLocations do
		table.insert(TeleportLocations_DropDownValues, Name)
	end

	table.sort(TeleportLocations_DropDownValues)

	local FishingZones = {}

	for _, Zone in next, workspace:WaitForChild("zones"):WaitForChild("fishing"):GetChildren() do
		if not FishingZones[Zone.Name] then
			FishingZones[Zone.Name] = Zone
		end
	end

	local FishingZones_DropDownValues = {}

	for Name, Zone in next, FishingZones do
		table.insert(FishingZones_DropDownValues, Name)
	end

	local function ResetTool()
		if CurrentTool then
			local ToolCache = LocalPlayer.Character:FindFirstChildOfClass("Tool")
			if CurrentTool then
				LocalPlayer.Character.Humanoid:UnequipTools()
				task.wait()
				ToolCache.Parent = LocalPlayer.Character
			end
		end
	end

	local function Unload()
		Toasts.CancelAllToasts()
		Utils.GenericToast(3, "Unloaded successfully!")

		Library:Unload()
		VelocityFly:Toggle(false)

		for _, Item in ipairs(Collection) do
			if typeof(Item) == "RBXScriptConnection" then
				Item:Disconnect()
			end

			if type(Item) == "thread" then
				coroutine.close(Item)
			end
		end

		local Inventory = WaitForTable(LocalPlayer.PlayerGui, { "hud", "safezone", "backpack" })
		if Inventory then
			Inventory.Visible = true
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end

		Utils.ToggleLocationCC(true)

		if GetToggleValue("ZoneFish") then
			task.defer(function()
				LocalPlayer.Character.Humanoid:UnequipTools()
				for _ = 1, 10 do
					task.wait()
					Utils.TP(ZoneFishOrigin.Position)
				end
				ZoneFishOrigin = nil
			end)
		end

		OnUnload:Fire()

		Toasts = nil
		Library = nil
		ThemeManager = nil
		SaveManager = nil
		VelocityFly = nil

		getgenv().Toggles = nil
		getgenv().Options = nil
		getgenv().sasware_fisch_unload = nil

		Unloaded = true
	end

	getgenv().sasware_fisch_unload = Unload

	-- Initalize UI (finally)

	local Window = Library:CreateWindow({
		Title = Title .. " | Fisch | " .. tostring(Version) .. SubVersion,
		Center = true,
		AutoShow = true,
	})

	local Tabs = {
		Main = Window:AddTab("Main"),
		Automation = Window:AddTab("Automation"),
		Visuals = Window:AddTab("Visuals"),
		Vulnerabilities = Window:AddTab("Vulnerabilities"),
		Settings = Window:AddTab("Settings"),
	}

	-- Main

	local FishingTabBox = Tabs.Main:AddLeftTabbox("Fishing")
	local CastingGroup = FishingTabBox:AddTab("Casting")
	local ReelingGroup = FishingTabBox:AddTab("Reeling")
	local OtherGroup = FishingTabBox:AddTab("Other")

	CastingGroup:AddToggle("AutoCast", {
		Text = "Auto-cast",
		Default = false,
		Tooltip = "Automatically casts for you.",
	})

	if not NO_HOOKING then
		CastingGroup:AddToggle("PerfectCast", {
			Text = "Always perfect [Server]",
			Default = false,
			Tooltip = "Makes your casts always perfect.",
		})
	end

	CastingGroup:AddToggle("InstantBob", {
		Text = "Instant bob [Blatant]",
		Default = false,
		Tooltip = "Forces the bobber to fall instantly.",
	})

	ReelingGroup:AddToggle("AutoReel", {
		Text = "Auto-reel [Legit]",
		Default = false,
		Tooltip = "Automatically plays the reel minigame.",
		Callback = function(Value: boolean)
			if Value then
				UI.Toggles.InstantReel:SetValue(false)
			end
		end,
	})

	ReelingGroup:AddToggle("InstantReel", {
		Text = "Insta-reel [Blatant]",
		Default = false,
		Tooltip = "Automatically reels in fish instantly.",
		Callback = function(Value: boolean)
			if Value then
				UI.Toggles.AutoReel:SetValue(false)
			end
		end,
	})

	ReelingGroup:AddToggle("PerfectReel", {
		Text = "Always perfect",
		Default = false,
		Tooltip = "Reels in fish perfectly!",
	})

	OtherGroup:AddToggle("AutoShake", {
		Text = "Auto shake",
		Default = false,
		Tooltip = "Automatically shakes the rod.",
	})

	OtherGroup:AddToggle("CenterShake", {
		Text = "Center-shake [Improves AutoShake]",
		Default = false,
		Tooltip = "Centers the shake UI.",
	})

	local TeleportsGroupBox = Tabs.Main:AddLeftGroupbox("Teleports")

	TeleportsGroupBox:AddDropdown("TeleportsDropdown", {
		Values = TeleportLocations_DropDownValues,
		Default = 1,
		Multi = false,

		Text = "Select location",
		Tooltip = "Location to teleport to",
	})

	TeleportsGroupBox:AddButton("Teleport", function()
		local Selected = GetOptionValue("TeleportsDropdown")
		local Position = TeleportLocations[Selected]

		if Position then
			Utils.TP(Position)
		end
	end)

	local UtilitiesGroupBox = Tabs.Main:AddRightGroupbox("Utilities")

	if not NO_HOOKING then
		UtilitiesGroupBox:AddToggle("FakeFishRadar", {
			Text = "Fish radar",
			Default = false,
			Tooltip = "A fake clientside fish radar.",
		}):AddKeyPicker("FakeFishRadarKeybind", {
			Default = "Insert",
			SyncToggleState = true,

			Mode = "Toggle",

			Text = "Fish radar",
			NoUI = false,
		})
	end

	UtilitiesGroupBox:AddToggle("DisablePeakEffects", {
		Text = "Disable oxygen/temperature",
		Default = false,
		Tooltip = "Disables peak effects."
	})

	UtilitiesGroupBox:AddToggle("InfiniteOxygen", {
		Text = "Infinite oxygen [Water]",
		Default = false,
		Tooltip = "Gives you infinite oxygen.",
	})

	UtilitiesGroupBox:AddToggle("AntiAFK", {
		Text = "Anti-AFK",
		Default = false,
		Tooltip = "Prevents you from being kicked for being AFK.",
	})

	UtilitiesGroupBox:AddDivider()
	UtilitiesGroupBox:AddLabel("Performance")

	UtilitiesGroupBox:AddToggle("DestroyFish", {
		Text = "No fish models",
		Default = false,
		Tooltip = "Automatically deletes fish models.",
	})

	UtilitiesGroupBox:AddToggle("DisableInventory", {
		Text = "Disable custom inventory [+FPS]",
		Default = false,
		Tooltip = "Disables the inventory UI.",
		Callback = function(Value: boolean)
			local Inventory = WaitForTable(LocalPlayer.PlayerGui, { "hud", "safezone", "backpack" })
			if Inventory then
				Inventory.Visible = not Value
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, Value)
			end
		end,
	})

	UtilitiesGroupBox:AddToggle("PersistentModels", {
		Text = "Persistent map [-Ping]",
		Default = false,
		Tooltip = "Attempts to prevent models from being unloaded.",
		Callback = function(Value: boolean)
			if Value then
				for _, Descendant in next, workspace:GetDescendants() do
					if Descendant:IsA("Model") then
						if Descendant.ModelStreamingMode ~= Enum.ModelStreamingMode.Persistent then
							CollectionService:AddTag(Descendant, "ForcePersistent")
							Descendant:SetAttribute("OldStreamingMode", Descendant.ModelStreamingMode.Name)
							Descendant.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
						end
					end
				end
			else
				for _, PersistentModel: Model in next, CollectionService:GetTagged("ForcePersistent") do
					if PersistentModel:GetAttribute("OldStreamingMode") then
						local OldStreamingMode: string = PersistentModel:GetAttribute("OldStreamingMode") :: string
						PersistentModel.ModelStreamingMode =
							Enum.ModelStreamingMode[OldStreamingMode] :: Enum.ModelStreamingMode
					else
						PersistentModel.ModelStreamingMode = Enum.ModelStreamingMode.Default
					end

					CollectionService:RemoveTag(PersistentModel, "ForcePersistent")
					PersistentModel:SetAttribute("OldStreamingMode", nil)
				end
			end
		end,
	})

	UtilitiesGroupBox:AddDivider()
	UtilitiesGroupBox:AddLabel("Tools")

	UtilitiesGroupBox:AddToggle("SpamTool", {
		Text = "Spam equipped tool",
		Default = false,
		Tooltip = "Spam-activates your equipped tool. [For crates]",
	})

	local ShopGroupBox = Tabs.Main:AddLeftGroupbox("Remote Shop")
	
	ShopGroupBox:AddDropdown("RemoteShopDropdown", {
		Values = {},
		Default = 1,
		Multi = false,
		Text = "Target item",
		Tooltip = "The item you want to buy",
	})

	ShopGroupBox:AddButton("Buy Item", function()
		local Selected = GetOptionValue("RemoteShopDropdown")
		local Item = workspace:WaitForChild("world"):WaitForChild("interactables"):FindFirstChild(Selected) :: Model?

		if Item then

			local Origin = LocalPlayer.Character:GetPivot()
			local LockPositionConnection = RunService.Heartbeat:Connect(function()
				Utils.TP(Item:GetPivot())
			end)

			task.wait(0.3)

			for _, Descendant in next, Item:GetDescendants() do
				if Descendant:IsA("ProximityPrompt") then
					fireproximityprompt(Descendant)
					break
				end
			end

			task.wait(0.3)

			LockPositionConnection:Disconnect()
			Utils.TP(Origin.Position)
			Utils:BreakVelocity()
		end
	end)

	local BoatGroupBox = Tabs.Main:AddRightGroupbox("Boat")

	BoatGroupBox:AddDropdown("BoatSpawnDropdown", {
		Values = State.OwnedBoats,
		Default = 1,
		Multi = false,

		Text = "Select boat",
		Tooltip = "Boat to spawn",
	})

	BoatGroupBox:AddButton("Remote-Spawn Boat", function()
		UI.Library:Toggle()

		local BoatSpawnLocation = LocalPlayer.Character:GetPivot().Position
		local BoatPreview = nil
		local BoatName = GetOptionValue("BoatSpawnDropdown")
		local ShipwrightNPC = Utils.GetNPC("Shipwright", true)

		if not ShipwrightNPC then
			Utils.GenericToast(3, "Shipwright not found.")
			UI.Library:Toggle()
			return
		end

		if not BoatName then
			Utils.GenericToast(3, "Please select a boat.")
			UI.Library:Toggle()
			return
		end

		if Interface.BoatModels:FindFirstChild(BoatName) then
			BoatPreview = Interface.BoatModels:FindFirstChild(BoatName):Clone()
			BoatPreview.Parent = Camera
		else
			BoatPreview = Instance.new("Model")
		end

		for _, Part in next, BoatPreview:GetDescendants() do
			if Part:IsA("BasePart") then
				Part.Anchored = true
				Part.CanCollide = false
				Part.CanTouch = false
			end
		end

		local Origin: CFrame = LocalPlayer.Character:GetPivot()
		Camera.CameraType = Enum.CameraType.Scriptable

		TweenService:Create(Camera, TweenInfo.new(0.5), {
			CFrame = CFrame.new(Origin.Position + Vector3.new(0, 80, 0), Origin.Position),
		}):Play()

		task.wait(0.5)

		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition

		local CameraMotionConnection
		CameraMotionConnection = RunService.RenderStepped:Connect(function()
			local Delta = UserInputService:GetMouseDelta()
			local X, Y = Delta.X, Delta.Y
			Camera.CFrame *= CFrame.Angles(0, math.rad(-X * 0.5), 0) * CFrame.Angles(math.rad(-Y * 0.5), 0, 0)

			local Params = RaycastParams.new()
			Params.FilterType = Enum.RaycastFilterType.Exclude
			Params.FilterDescendantsInstances = { LocalPlayer.Character, BoatPreview }

			local CameraHit = workspace:Raycast(Camera.CFrame.Position, Camera.CFrame.LookVector * 500, Params)

			if CameraHit then
				BoatSpawnLocation = CameraHit.Position + Vector3.new(0, 10, 0)
				BoatPreview:PivotTo(CFrame.new(BoatSpawnLocation))
			end
		end)

		local InputConnection
		InputConnection = UserInputService.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				InputConnection:Disconnect()
				CameraMotionConnection:Disconnect()
				Camera.CameraType = Enum.CameraType.Custom
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default

				LocalPlayer.Character:PivotTo(ShipwrightNPC:GetPivot())

				task.wait(0.3)
				fireproximityprompt(ShipwrightNPC.dialogprompt)

				local Result = ShipwrightNPC.shipwright.giveUI:InvokeServer()
				BoatPreview:Destroy()

				if Result then
					LocalPlayer.PlayerGui.hud.safezone.shipwright.ships.main.safezone.spawnattempt:FireServer(BoatName)
					-- this game is so bad
					repeat
						task.wait(0.5)
					until Interface.ActiveBoats:FindFirstChild(LocalPlayer.Name)

					local Ship =
						Interface.ActiveBoats:FindFirstChild(LocalPlayer.Name):FindFirstChildOfClass("Model") :: Model
					local Seat = Ship:FindFirstChildOfClass("VehicleSeat")
					local SitPrompt = Seat:WaitForChild("sitprompt")

					task.wait(0.5)
					fireproximityprompt(SitPrompt)
					task.wait(0.5)

					for i = 1, 60 do
						task.wait()
						Ship:PivotTo(CFrame.new(BoatSpawnLocation))
					end

					Ship.PlanePart.Rotation = Vector3.new(0, 0, 0)

					local WaterRayParams = RaycastParams.new()
					WaterRayParams.FilterType = Enum.RaycastFilterType.Include
					WaterRayParams.FilterDescendantsInstances = { workspace.Terrain }
					WaterRayParams.IgnoreWater = false

					local WaterHeight =
						workspace:Raycast(Ship.PlanePart.Position + Vector3.new(0, 100, 0), Vector3.new(0, -255, 0))

					if WaterHeight then
						Ship.PlanePart.Position = Ship.PlanePart.Position * Vector3.new(1, 0, 1)
							+ Vector3.new(0, WaterHeight.Position.Y, 0)
					end
				end

				UI.Library:Toggle()
			end
		end)
	end)

	local AutomationMiscGroup = Tabs.Automation:AddLeftGroupbox("Enviromental")

	AutomationMiscGroup:AddToggle("AutoMeteor", {
		Text = "Auto-Meteor",
		Default = false,
		Tooltip = "Automatically grabs item from meteor.",
	})

	local AutomationFishingGroup = Tabs.Automation:AddRightGroupbox("Fishing")

	AutomationFishingGroup:AddToggle("ZoneFish", {
		Text = "Zone-fish",
		Default = false,
		Tooltip = "Zones fish for you.",
		Callback = function(Value: boolean)
			if Value then
				UI.Toggles.InfiniteOxygen:SetValue(true)
				ZoneFishOrigin = LocalPlayer.Character:GetPivot()
			else
				if ZoneFishOrigin then
					LocalPlayer.Character.Humanoid:UnequipTools()
					for _ = 1, 10 do
						task.wait()
						Utils.TP(ZoneFishOrigin.Position)
					end
					ZoneFishOrigin = nil
				end
			end
		end,
	})

	AutomationFishingGroup:AddDropdown("ZoneFishDropdown", {
		Values = FishingZones_DropDownValues,
		Default = 1,
		Multi = false,
		Text = "Select zone",
		Tooltip = "Zone to fish in",
	})

	local GameVisualsGroup = Tabs.Visuals:AddLeftGroupbox("In-game")

	GameVisualsGroup:AddToggle("NoLocationCC", {
		Text = "No ambient",
		Default = false,
		Tooltip = "Disables the location Color-Correction.",
	})

	local GameplayDisruptionGroup = Tabs.Vulnerabilities:AddLeftGroupbox("Gameplay Disruption")

	GameplayDisruptionGroup:AddToggle("ServerStresser", {
		Text = "Lag/Crash server",
		Default = false,
		Tooltip = "Spams tools to lag the server.",
		Callback = function(Value : boolean)
			if not Value then
				game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
			else
				Utils.TP(LocalPlayer.Character:GetPivot().Position + Vector3.new(0, 9e9, 0))
			end
		end
	})

	GameplayDisruptionGroup:AddLabel("The server lagger is irreversible and you will be forced to rejoin if you want to disable it.", true)

	Tabs.Vulnerabilities:AddRightGroupbox("Vulnerabilities"):AddLabel("dupe coming 2025")

	-- Settings

	local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu")

	MenuGroup:AddButton("Unload", Unload)

	Collect(RunService.RenderStepped:Connect(function()
		Library:SetWatermark("Current connections: " .. #Collection)
	end))

	MenuGroup:AddLabel("Menu bind")
		:AddKeyPicker("MenuKeybind", { Default = "RightControl", NoUI = true, Text = "Menu keybind" })
	MenuGroup:AddToggle("Rainbow", {
		Text = "Rainbow UI",
		Default = false,
		Tooltip = "Rainbow UI colors.",
	})

	Library.ToggleKeybind = UI.Options.MenuKeybind

	MenuGroup:AddToggle("ShowCustomCursor", {
		Text = "Custom Cursor",
		Default = true,
		Callback = function(Value) Library.ShowCustomCursor = Value end
	})
	Library.ShowCustomCursor = UI.Toggles.ShowCustomCursor.Value

	ThemeManager:SetLibrary(Library)
	SaveManager:SetLibrary(Library)

	SaveManager:IgnoreThemeSettings()

	SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

	ThemeManager:SetFolder("sasware_fisch")
	SaveManager:SetFolder("sasware_fisch/main")

	SaveManager:BuildConfigSection(Tabs.Settings)

	ThemeManager:ApplyToTab(Tabs.Settings)

	-- Initalize hooks / script modifications

	if not NO_HOOKING then
		local FakeFishRadar = Interface.FishRadar:Clone()
		local FishRadarTool = Instance.new("Tool")

		for _, Child in next, FakeFishRadar:GetChildren() do
			Child.Parent = FishRadarTool
		end

		FakeFishRadar:Destroy()
		FishRadarTool.radar.Enabled = false
		FishRadarTool.radar.ui.UIStroke.Color = Color3.fromRGB(204, 128, 255)
		FishRadarTool.Parent = LocalPlayer.PlayerScripts

		UI.Toggles.FakeFishRadar:OnChanged(function(Value: boolean)
			if Value == false and PreAutoloadConfig then
				return -- yes.
			end

			for _, Connection in next, getconnections(FishRadarTool.Activated) do
				local cf = Connection.Function
				debug.setupvalue(cf, 1, false) -- disable debounce lawl

				setthreadidentity(2)
				task.spawn(Connection.Function) -- why does seliware call the function in THIS thread when you fire it
				setthreadidentity(7)
			end

			FishRadarTool.radar.Enabled = true
		end)

		OnUnload.Event:Once(function()
			FishRadarTool:Destroy()
		end)
	end

	local FakeTank = Instance.new("Glue")
	FakeTank.Name = "DivingTank"
	FakeTank:SetAttribute("Tier", 9e9)

	OnUnload.Event:Once(function()
		FakeTank:Destroy()
	end)

	UI.Toggles.InfiniteOxygen:OnChanged(function(Value: boolean)
		if Value then
			FakeTank.Parent = LocalPlayer.Character
		else
			FakeTank.Parent = nil
		end
	end)

	setthreadidentity(7) -- some edge cases with seliware's connection:Fire bugs colliding with unload race conditions cause
	-- identity to be reset to 3 (or maybe it was 2 i forgot)

	Utils.BoatsChanged()

	Collect(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		Camera = workspace.CurrentCamera
	end))

	Collect(Interface.PlayerData.Boats.AncestryChanged:Connect(Utils.BoatsChanged))

	Collect(workspace:WaitForChild("active").ChildAdded:Connect(function(Child: Instance)
		if Child:IsA("Model") then
			local Fish = Child:WaitForChild("Fish", 1)

			if Fish then
				if GetToggleValue("DestroyFish") then
					task.wait()
					Child:Destroy()
				end
			end
		end
	end))

	Collect(Interface.Inventory:GetPropertyChangedSignal("Visible"):Connect(function()
		if GetToggleValue("DisableInventory") then
			task.wait()
			Interface.Inventory.Visible = false
		end
	end))

	Collect(workspace.DescendantAdded:Connect(function(Descendant: Instance)
		if Descendant:IsA("Model") then
			if GetToggleValue("PersistentModels") then
				if Descendant.ModelStreamingMode ~= Enum.ModelStreamingMode.Persistent then
					CollectionService:AddTag(Descendant, "ForcePersistent")
					Descendant:SetAttribute("OldStreamingMode", Descendant.ModelStreamingMode.Name)
					Descendant.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
				end
			end
		end
	end))

	Collect(Interface.MeteorItems.ChildAdded:Connect(function(Item: Model)
		if GetToggleValue("AutoMeteor") then
			State.GettingMeteor = true

			local Origin = LocalPlayer.Character:GetPivot()
			local Prompt: ProximityPrompt = WaitForTable(Item, { "Center", "prompt" }, 5)
			local Center: Part = Prompt.Parent :: Part

			local TPConnection = RunService.PostSimulation:Connect(function()
				Utils.TP(Center:GetPivot() - (Vector3.yAxis * 5))
				fireproximityprompt(Prompt)
			end)

			task.delay(4, function()
				TPConnection:Disconnect()
				Utils.TP(Origin)
				State.GettingMeteor = false
			end)
		end
	end))

	if not NO_HOOKING then
		local oldindex
		oldindex = hookmetamethod(game, "__index", function(...)
			if not Unloaded then
				if not checkcaller() then
					local Args = { ... } -- i forgot argguard wasnt a thing anymore
					local self, key = Args[1], Args[2]

					if self == Interface.Inventory and key == "Visible" then
						local callingscript = getcallingscript()

						if callingscript and (not game.IsDescendantOf(callingscript, Interface.Inventory)) then
							return true -- for some reason when the backpack isn't visible it disables the menu buttons
						end
					end
				end
			end

			return oldindex(...)
		end)

		local oldnamecall
		oldnamecall = hookmetamethod(game, "__namecall", function(...)
			if not Unloaded then
				if not checkcaller() then
					local Method = getnamecallmethod()

					local Args = { ... }
					local self = table.remove(Args, 1)

					if Method == "FireServer" then
						if self == Remotes.ReelFinished then
							if GetToggleValue("PerfectReel") then
								Args[1] = 100 -- Reel percentage
								Args[2] = true -- If the reel was perfect
							end
						elseif tostring(self) == "cast" then -- ultra detectable but i dont care because im sigma.
							if GetToggleValue("PerfectCast") then
								Args[1] = 100 -- Cast percentage
							end
						end

						return oldnamecall(self, unpack(Args))
					end
				end
			end

			return oldnamecall(...)
		end)
	end

	local ShopUpdateCoroutine = coroutine.create(function()
		while task.wait(1) do
			Utils.UpdateShopDropdown()
		end
	end)

	local AutoClickCoroutine = coroutine.create(function()
		function Utils.MountShakeUI(ShakeUI: ScreenGui)
			local SafeZone: Frame? = ShakeUI:WaitForChild("safezone", 5) :: Frame?

			local function HandleButton(Button: ImageButton)
				Button.Selectable = true -- For some reason this is false for the first 0.2 seconds.

				GuiService.AutoSelectGuiEnabled = false
				GuiService.GuiNavigationEnabled = true

				if EnsureInstance(Button) then
					GuiService.SelectedObject = Button
					task.wait()
					VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
					VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
					task.wait()
				end

				GuiService.AutoSelectGuiEnabled = true
				GuiService.GuiNavigationEnabled = false
				GuiService.SelectedObject = nil
			end

			if not SafeZone then
				dbgwarn("Unable to mount shake UI.")
				return
			end

			if GetToggleValue("CenterShake") then
				local Connect = SafeZone:WaitForChild("connect", 1)

				if Connect then
					Connect.Enabled = false -- this script locks the size of the safezone, so we disable it.
				end

				SafeZone.Size = UDim2.fromOffset(0, 0)
				SafeZone.Position = UDim2.fromScale(0.5, 0.5)
				SafeZone.AnchorPoint = Vector2.new(0.5, 0.5)
			end

			if GetToggleValue("AutoShake") then
				local Connection = SafeZone.ChildAdded:Connect(function(Child)
					if Child:IsA("ImageButton") then
						local Done = false

						task.spawn(function()
							repeat
								RunService.RenderStepped:Wait()
								HandleButton(Child)
							until Done
						end)

						task.spawn(function()
							repeat
								RunService.RenderStepped:Wait()
							until (not Child) or (not Child:IsDescendantOf(SafeZone))
							Done = true
						end)
					end
				end)

				repeat
					wait()
				until not SafeZone:IsDescendantOf(LocalPlayer.PlayerGui)
				Connection:Disconnect()
			end
		end

		Collect(LocalPlayer.PlayerGui.ChildAdded:Connect(function(Child: Instance)
			if Child.Name == "shakeui" and Child:IsA("ScreenGui") then
				Utils.MountShakeUI(Child)
			end
		end))
	end)

	local AutoReelCoroutine = coroutine.create(function()
		while true do
			RunService.RenderStepped:Wait()

			local ReelUI: ScreenGui = LocalPlayer.PlayerGui:FindFirstChild("reel")

			if not ReelUI then
				continue
			end

			if GetToggleValue("InstantReel") then
				local Bar = ReelUI:FindFirstChild("bar")

				if Bar then
					local ReelScript = Bar:FindFirstChild("reel")
					if ReelScript and ReelScript.Enabled == true then
						Remotes.ReelFinished:FireServer(100, GetToggleValue("PerfectReel"))
					end
				end
			elseif GetToggleValue("AutoReel") then
				local Bar = ReelUI:FindFirstChild("bar")

				if not Bar then
					continue
				end

				local PlayerBar: Frame = Bar:FindFirstChild("playerbar")
				local TargetBar: Frame = Bar:FindFirstChild("fish")

				while Bar and ReelUI:IsDescendantOf(LocalPlayer.PlayerGui) do
					RunService.RenderStepped:Wait()
					local UnfilteredTargetPosition = PlayerBar.Position:Lerp(TargetBar.Position, 0.7)
					local TargetPosition = UDim2.fromScale(
						math.clamp(UnfilteredTargetPosition.X.Scale, 0.15, 0.85),
						UnfilteredTargetPosition.Y.Scale
					)

					PlayerBar.Position = TargetPosition
				end
			end
		end
	end)

	local AutoCastCoroutine = coroutine.create(function()
		local LastCastAttempt = 0
        local ResetCooldown = 6 -- Cooldown duration in seconds

        while task.wait(0.1) do
            if GetToggleValue("AutoCast") then
                pcall(function()
                    if not CurrentTool then
                        return
                    end
        
                    local Values = CurrentTool:FindFirstChild("values")
                    if CurrentTool and Values then
                        local Events = CurrentTool:FindFirstChild("events")
        
                        -- Fix for tool resetting spam
                        if
                            Values:FindFirstChild("bite")
                            and Values.bite.Value == true
                            and Values.casted.Value == true
                        then
                            if (not LocalPlayer.PlayerGui:FindFirstChild("reel")) and (tick() - LastResetAttempt > ResetCooldown) then
                                LastResetAttempt = tick()
                                ResetTool()
                            end
                        end
        
                        -- Another fix
                        if Utils.CountInstances(LocalPlayer.PlayerGui, "reel") > 1 then
                            if tick() - LastResetAttempt > ResetCooldown then
                                LastResetAttempt = tick()
                                ResetTool()
                                for _, Child in next, LocalPlayer.PlayerGui:GetChildren() do
                                    if Child.Name == "reel" then
                                        Child:Destroy()
                                    end
                                end
                            end
                        end


						if Values.casted.Value == false then
							LastCastAttempt = tick()

							local AnimationFolder = ReplicatedStorage:WaitForChild("resources")
								:WaitForChild("animations")

							local CastAnimation: AnimationTrack = LocalPlayer.Character
								:FindFirstChild("Humanoid")
								:LoadAnimation(AnimationFolder.fishing.throw)
							CastAnimation.Priority = Enum.AnimationPriority.Action3
							CastAnimation:Play()
							Events.cast:FireServer(100, 1)

							CastAnimation.Stopped:Once(function()
								CastAnimation:Destroy()

								local WaitingAnimation: AnimationTrack = LocalPlayer.Character
									:FindFirstChild("Humanoid")
									:LoadAnimation(AnimationFolder.fishing.waiting)
								WaitingAnimation.Priority = Enum.AnimationPriority.Action3
								WaitingAnimation:Play()

								local UnequippedLoop, CastConnection

								CastConnection = Values.casted.Changed:Once(function()
									WaitingAnimation:Stop()
									WaitingAnimation:Destroy()
									coroutine.close(UnequippedLoop)
								end)

								UnequippedLoop = coroutine.create(function()
									repeat
										task.wait()
									until not CurrentTool
									WaitingAnimation:Stop()
									WaitingAnimation:Destroy()
									CastConnection:Disconnect()
								end)

								coroutine.resume(UnequippedLoop)
							end)
						end
					end
				end)
			end
		end
	end)

	local ServerStressCoroutine = coroutine.create(function()

		local Backpack = LocalPlayer.Backpack

		local function IsFish(Tool : Tool)
			return Tool:FindFirstChild("fishscript") or (Tool:GetAttribute("IsFish") == true)
		end

		while task.wait(5) do

			if not GetToggleValue("ServerStresser") then
				continue
			end

			for i, Tool in next, Backpack:GetChildren() do
				task.spawn(function()
					if IsFish(Tool) then

						Tool:SetAttribute("IsFish", true)
	
						local FishModel = Tool:FindFirstChild("Fish")
	
						if FishModel then
							FishModel:Destroy()
						end
	
						Tool.Parent = LocalPlayer.Character
	
					end
				end)
			end

			LocalPlayer.Character.Humanoid:UnequipTools()

		end

	end)

	-- VULNERABILTY SECTION: PRONE TO DETECTION & PATCHES

	-- all patched for now

	-- yea thats the vulnerability section lol

	Collect(RunService.RenderStepped:Connect(function()
		if GetToggleValue("SpamTool") then
			if CurrentTool then
				for i = 20, 1, -1 do
					CurrentTool:Activate()
				end
			end
		end

		UserInputService.MouseIconEnabled = not GetToggleValue("ShowCustomCursor") or not UI.Library.Toggled

		if GetToggleValue("NoLocationCC") then
			Utils.ToggleLocationCC(false)
		else
			Utils.ToggleLocationCC(true)
		end
	end))

	Collect(RunService.PostSimulation:Connect(function()
		if GetToggleValue("ZoneFish") then
			if State.GettingMeteor then
				return -- dont conflict with meteor grabbing
			end

			for _, Part in next, LocalPlayer.Character:GetDescendants() do
				if Part:IsA("BasePart") then
					Part.CanTouch = false -- killzones and such
				end
			end

			local Zone = FishingZones[GetOptionValue("ZoneFishDropdown")]

			if Zone then
				local Origin = Zone:GetPivot()
				Utils.TP(Origin - Vector3.new(0, 20, 0))

				if CurrentTool then
					local Bobber = CurrentTool:FindFirstChild("bobber")
					if Bobber then
						local Rope = Bobber:FindFirstChildOfClass("RopeConstraint")
						if Rope then
							Rope.Length = 9e9
						end
						Bobber:PivotTo(Origin)
					end
				end
			end
		elseif GetToggleValue("InstantBob") then
			if CurrentTool then
				local Bobber = CurrentTool:FindFirstChild("bobber")
				if Bobber then
					local Params = RaycastParams.new()

					Params.FilterType = Enum.RaycastFilterType.Include
					Params.FilterDescendantsInstances = { workspace.Terrain }

					local RaycastResult = workspace:Raycast(Bobber.Position, -Vector3.yAxis * 100, Params)

					if RaycastResult then
						if RaycastResult.Instance:IsA("Terrain") then
							Bobber:PivotTo(CFrame.new(RaycastResult.Position))
						end
					end
				end
			end
		end
	end))

	Collect(LocalPlayer.Idled:Connect(function()
		if GetToggleValue("AntiAFK") then -- pasted from infinite yield weeeeeeeee
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end
	end))

	-- Start coroutines
	coroutine.resume(ServerStressCoroutine)
	coroutine.resume(AutoClickCoroutine)
	coroutine.resume(AutoReelCoroutine)
	coroutine.resume(AutoCastCoroutine)
	coroutine.resume(ShopUpdateCoroutine)
	Collect(ServerStressCoroutine)
	Collect(AutoClickCoroutine)
	Collect(AutoReelCoroutine)
	Collect(AutoCastCoroutine)
	Collect(ShopUpdateCoroutine)

	Collect(LocalPlayer.CharacterAdded:Connect(Utils.CharacterAdded))
	Collect(RunService.RenderStepped:Connect(function()
		if GetToggleValue("Rainbow") then
			Library.AccentColor = Library.CurrentRainbowColor
			Library:UpdateColorsUsingRegistry()
		end
	end))

	OnUnload.Event:Once(function()
		for _, PersistentModel: Model in next, CollectionService:GetTagged("ForcePersistent") do
			if PersistentModel:GetAttribute("OldStreamingMode") then
				local OldStreamingMode: string = PersistentModel:GetAttribute("OldStreamingMode") :: string
				PersistentModel.ModelStreamingMode =
					Enum.ModelStreamingMode[OldStreamingMode] :: Enum.ModelStreamingMode
			else
				PersistentModel.ModelStreamingMode = Enum.ModelStreamingMode.Default
			end

			CollectionService:RemoveTag(PersistentModel, "ForcePersistent")
			PersistentModel:SetAttribute("OldStreamingMode", nil)
		end

	end)

	if LocalPlayer.Character then
		Utils.CharacterAdded(LocalPlayer.Character)
	end

	SaveManager:LoadAutoloadConfig()
	PreAutoloadConfig = false

	Utils.GameNotify("Sasware [Fisch] loaded successfully!")

	-- DONT REMOVE this end remember this is wrapped in a pcall
end)

if not Success then
	warn("Error:", Error)
end

-- task.wait(220)
-- getgenv().sasware_fisch_unload()
