module DE0BattleShip(clk0, B, dispHEX0, dispHEX1, dispHEX2, dispHEX3);
	
	//Inputs.
	input clk0; 		//50MHz
	input [2:0] B;
	
	parameter n = 3;	//only used in the lfsrs
	
	//background registers that do all the work
	reg [0:3] upcounter_X, 
				 upcounter_Y;
	//3 bit - registers: can count from 0 to 8
	reg [0:2] lfsrX, 
				 lfsrY, 
				 lfsrDir;
	
	//Display Outputs
	output reg [0:7] dispHEX0, 
						  dispHEX1, 
						  dispHEX2, 
						  dispHEX3;
	//This multidimensional array below can't be used as an output :( so we use the registers above to do that
	reg [0:7] dispHEX [0:3];
	
	
	//Game Variables: Ship Coordinates, Statistics, States
	reg [0:4] totalTries, totalHits;//Can hold values from 0 to 30;Random note: Same as reg [0:0] totalTries [0:4]
	//Temp Values (holds instantanous lfsr data)
	reg [0:2] shipCoordX0, 
				 shipCoordY0, 
				 shipDirection;
	//Main States
	parameter startScreen 	 	 = 3'b000, 
				 setupMode	 		 = 3'b001,
				 playMode	 		 = 3'b010,
				 result	 			 = 3'b011,
				 hit				 	 = 3'b100,
				 splash				 = 3'b101,
				 statScore 		 	 = 3'b110;
	
	//States under nextSetupStage (under setupMode)
	//setupMode -> nextSetupStage
	parameter generateShipData = 2'b00, //generateDirection = 2'b00,
				 generateCoord		 = 2'b01,
				 validCoord	 			 = 2'b10,
				 placeShip			 = 2'b11;
				 
	//states under operation 
	//declared under (settingMode -> validCoord -> shipDirection)
	//used during for loop under 'SETTING ALL OTHER POINTS'
	parameter addX			 = 3'b000,
				 subX			 = 3'b001,
				 keepX		 = 3'b010,
				 addY			 = 3'b011,
				 subY			 = 3'b100,
				 keepY		 = 3'b101;
				 
	reg [0:3] shipID, 				//between 1 and 6
				 comparingShipID, 	//under setupMode when detecting side collisions
				 nextComparingShipID;//460: under setupMode when detecting side collisions
	reg [0:1] shipLength;			//between 2 and 4
	reg [0:2] X_operation;				//under a for loop in setupMode when placing ships
	reg [0:2] Y_operation;				//under a for loop in setupMode when placing ships
	reg 		 collisionDetected;	//used under setupMode when checking for a collision 
	reg 		 matchFound;
	reg 		 W;
				 
	//Current state(y); Next State(Y)
	reg [0:2] y,Y;
	reg [0:2] setupStage;
	reg [0:2] nextSetupStage;
	
	
				 
	//Actual ship coordinate registers
	//Arrays of 18 elements that are each 3-bits long (X and Y coordinates)
	reg [0:2] shipX [0:17]; 	
	reg [0:2] shipY [0:17];
	integer startIndex, 			//206: under setupMode
			  lastIndex,
			  shipIndex,
			  currentIndex,  		//386: under setupMode when detecting collisions
			  comparingIndex;			//For iterating through each coordinate for each ship
	
	initial 
	begin
		lfsrX 		= 3;
		lfsrY			= 6;
		lfsrDir		= 5;
	end
	
	//Begin lfsrX
	always@(posedge clk0) begin
		if(lfsrX == 6) begin
			lfsrX <= 1;
		end else begin
			lfsrX <= lfsrX + 1;					//THIS IS NOT REALLY AN LFSR! IT'S AN UP COUNTER!
		end
	end 					
	//End lfsrX
	
	//Begin lfsrY
	always@(clk0) begin
		if(lfsrY == 1) begin						//THIS IS NOT REALLY AN LFSR! IT'S A DOWN COUNTER!
			lfsrY <= 6;
		end else begin
			lfsrY <= lfsrY - 1;
		end
	end
	//End lfsrY
	integer k;
	//Begin lfsrDir 
	always@(clk0) begin
		lfsrDir[0] <= lfsrDir[n-1] ^ lfsrDir[n-2];	//feedback mechanism
		
		for(k = 0; k < (n-1); k = k+1) begin
			lfsrDir[k+1] <= lfsrDir[k];					//shifting
		end

	end
	//End lfsrDir
	
	//Initialize displays, counters, and lfsrs
	initial 
	begin
		//Changed values from 1 to 0
		dispHEX[0] <=0; dispHEX0	<= 0;
		dispHEX[1] <=0; dispHEX1	<= 0;
		dispHEX[2] <=0; dispHEX2	<= 0;
		dispHEX[3] <=0; dispHEX3	<= 0;
		
		upcounter_X <= 1;
		upcounter_Y <= 1;
	end	
	
	//User X-coordinate input counter
	always@(negedge B[2]) begin
		if(y == playMode) begin	// &&!(hit||splash)) begin
			if(upcounter_X == 6) 
				upcounter_X <= 1;
			else 
				upcounter_X <= upcounter_X + 1;
		end
	end
	
	//UserY-Coordinate input counter
	always@(negedge B[1]) begin
		if(y == playMode) begin 	// && !(hit||splash))begin
			if(upcounter_Y == 6) 
				upcounter_Y <= 1;
			else 
				upcounter_Y <= upcounter_Y + 1;
		end
	end
	//-----------------ACTUAL GAME--------------------------------------------------------------------------------------------------
	
	integer i0;
	
	initial 
	begin
		//Initialize every ship at (0,0) (An invalid location)
		for(i0 = 0; i0 < 18; i0 = i0 + 1) begin
			shipX[i0] <= 0;
			shipY[i0] <= 0;
		end
		
		//testing conditions
		shipX[17] <= 2;
		shipY[17] <= 4;
		
		shipX[3] <= 3;
		shipY[3] <= 6;
		
		matchFound = 0;
		
		//Start placing ship 6 first
		shipID = 6;
		shipLength = 4;
		
		y = startScreen;
		totalHits 	<= 0;
		totalTries 	<= 0;
		
		W = 1;
	end
	
	//Sequential Block
	
	always @ (negedge B[0]) begin//, posedge setupDone) 
		y <= Y;
	end
	
	
	/*
	always @ (negedge W)
	begin
		nextSetupStage <= nextSetupStage;
		W = 1;
	end
	*/
	integer checkingIndex;
	always @(clk0) begin
		//setting up shipIDs, sets us to start at ship 6 
		setupStage <= nextSetupStage;
		
		case(shipID)
			default: shipID = 6;
			6: begin 
					startIndex = 17;
					lastIndex = 14;
					shipLength = 4;
					//nextShipID = 5;
				end
			5: begin
					startIndex = 13;
					lastIndex = 10;
					shipLength = 4;
					//nextShipID = 4;
				end
			4:	begin
					startIndex = 9;
					lastIndex = 7;
					shipLength = 3;
					//nextShipID = 3;
				end
			3:	begin
					startIndex = 6;
					lastIndex = 4;
					shipLength = 3;
					//nextShipID = 2;
				end
			2: begin
					startIndex = 3;
					lastIndex = 2;
					shipLength = 2;
					//nextShipID = 1;
				end
			1: begin
					startIndex = 1;
					lastIndex = 0;
					shipLength = 2;
					
					//lastShip = 1; 10/1/2015 Uncomment this 
					//Y = playMode;
					//nextShipID = 6;
				end
		endcase
		
		//Main case statement w/ startScreen, setupMode, playMode, hit, splash, statScore
		//*********************************BEGIN MAIN CASE STATEMENT*********************************************************************
		case(y)
			//When device is ON
			default: Y = startScreen;
			
			startScreen: begin
				//Make it blink when possible
				dispHEX[3] = 8'b00110001; 	//P
				dispHEX[2] = 8'b11100011; 	//L
				dispHEX[1] = 8'b00010001; 	//A
				dispHEX[0] = 8'b10001001;	//Y
				
				
				dispHEX0 <= dispHEX[0];
				dispHEX1 <= dispHEX[1];
				dispHEX2 <= dispHEX[2];
				dispHEX3 <= dispHEX[3];
				
				Y = playMode;
			end
			
			//When we press btn0 to start the game and when we play 
			playMode: begin
				//Brackets
				//--------------01234567
				dispHEX[3] = 8'b01100011; 
				dispHEX[0] = 8'b00001111;
								
				//Displays values on counter 1
				if(upcounter_X == 1) dispHEX[2] = 8'b10011110;
				if(upcounter_X == 2) dispHEX[2] = 8'b00100100;
				if(upcounter_X == 3) dispHEX[2] = 8'b00001100;
				if(upcounter_X == 4) dispHEX[2] = 8'b10011000;
				if(upcounter_X == 5) dispHEX[2] = 8'b01001000;
				if(upcounter_X == 6) dispHEX[2] = 8'b01000000;
													
				//Displays values on counter 2			
				if(upcounter_Y == 1) dispHEX[1] = 8'b10011111;
				if(upcounter_Y == 2) dispHEX[1] = 8'b00100101;
				if(upcounter_Y == 3) dispHEX[1] = 8'b00001101;
				if(upcounter_Y == 4) dispHEX[1] = 8'b10011001;
				if(upcounter_Y == 5) dispHEX[1] = 8'b01001001;
				if(upcounter_Y == 6) dispHEX[1] = 8'b01000001;
				
			
				Y = result;
				
				//Reset the match found
				matchFound = 0;
				
			end 
			
			//After pressing BTN0
			result: begin
			/*
				//Little piece of history:
				for(checkingIndex = 0; checkingIndex < 18; checkingIndex = checkingIndex + 1)
				begin
					if(upcounter_X == shipX[checkingIndex])
					begin
						if(upcounter_Y == shipY[checkingIndex])
						begin
							Y = hit;
						end
						else if(checkingIndex == 17)
							Y = splash;
					end
				end
			*/	
				//checkingIndex = 0;
				for(checkingIndex = 0; checkingIndex < 18; checkingIndex = checkingIndex + 1) begin: checkLoop
					if(!matchFound) begin
						if((shipX[checkingIndex] == upcounter_X) && (shipY[checkingIndex]) == upcounter_Y) begin
							//If X and Y coordinate match
							dispHEX[3] = 8'b11111111;  //Blank		
							dispHEX[2] = 8'b10010001;	//H
							dispHEX[1] = 8'b11110011;	//I
							dispHEX[0] = 8'b11100001;	//T
							
							//Y = statScore;
							Y = startScreen;
						
							matchFound = 1;
							//disable checkLoop; <- causes problems
						end else if(checkingIndex == 17) begin
							//If X-coordinate matched but Y-coordinate didn't
							dispHEX[3] = 8'b01001000;	//S - CHANGE LAST 0 TO 1
							dispHEX[2] = 8'b00110001;	//P
							dispHEX[1] = 8'b11100011;	//L
							dispHEX[0] = 8'b10010001;	//H
									
							//Y = statScore;
							Y = startScreen;
							matchFound = 0;
							disable checkLoop;
						end
					end// END if(!match) statement
				end
			end
			//After pressing BTN0
			
			/*
			statScore: 
			begin
		
				//display hits/plays ratio
				Y = startScreen;
							
			end
			*/
			
			//START COMMENTING OUT HERE IF STUFF DOESNT WORK
			setupMode:  begin
				dispHEX[3] = 8'b11111110; 	//.
				dispHEX[2] = 8'b11111110; 	//.
				dispHEX[1] = 8'b11111110; 	//.
				dispHEX[0] = 8'b11111110;	//.
					
				//setting up shipIDs, sets us to start at ship 6 
				
				
				//end shipID case
				//Actual Setup Process	
				case(setupStage) //commented out sections at 387
					generateShipData: begin
						//if(getDir)
						//begin
							shipDirection <= lfsrDir;
						//end
						
						shipCoordX0 <= lfsrX;
						shipCoordY0 <= lfsrY;
						
						nextSetupStage = validCoord;
					end
		
					validCoord:	begin
					
						case(shipDirection)		
							//magic number 7 works! a ship of length 4 in direction 0 cannot exist anywhere where X > 3, etc
							//positive directions: (7 - shipLength)
							//negative directions: shipLength
							//maybe switch each of these if statements to while statements!!!!
							0:	begin
									if(shipCoordX0 > (7 - shipLength)) begin
										//shipCoordX0 <= lfsrX;
										nextSetupStage = generateShipData;
									end else
									X_operation = addX;
									Y_operation = keepY;
									nextSetupStage = placeShip;
								end
							1: begin
									if((shipCoordX0 > (7 - shipLength)) || (shipCoordY0 > (7 - shipLength))) begin
										//if(shipCoordX0 > (7 - shipLength))	shipCoordX0 <= lfsrX;
										//if(shipCoordY0 > (7 - shipLength))	shipCoordY0 <= lfsrY;
										nextSetupStage = generateShipData;
									end else
									X_operation = addX;
									Y_operation = addY;
									nextSetupStage = placeShip;
								end
							2: begin
									if(shipCoordY0 > (7 - shipLength)) begin
										//shipCoordY0 <= lfsrY;
										nextSetupStage = generateShipData;
									end else
									X_operation = keepX;
									Y_operation = addY;
									nextSetupStage = placeShip;
								end
							3: begin
									if((shipCoordX0 < shipLength)||(shipCoordY0 > (7 - shipLength))) begin
										//if(shipCoordX0 < shipLength)			shipCoordX0 <= lfsrX;
										//if(shipCoordY0 > (7 - shipLength))	shipCoordY0 <= lfsrY;
										nextSetupStage = generateShipData;
									end else
									X_operation = subX;
									Y_operation = addY;
									nextSetupStage = placeShip;
								end
								
							4: begin
									if(shipCoordX0 < shipLength) begin
										//shipCoordX0 <= lfsrX;
										nextSetupStage = generateShipData;
									end else
									X_operation = subX;
									Y_operation = keepY;
									nextSetupStage = placeShip;
								end
								
							5: begin
									if((shipCoordX0 < shipLength) || (shipCoordY0 < shipLength)) begin
										//if(shipCoordX0 < shipLength)	shipCoordX0 <= lfsrX;
										//if(shipCoordY0 < shipLength)	shipCoordY0 <= lfsrY;
										nextSetupStage = generateShipData;
									end else
									X_operation = subX;
									Y_operation = subY;
									nextSetupStage = placeShip;
								end
							6: begin
									if(shipCoordY0 < shipLength) begin
										//shipCoordY0 <= lfsrY;
										nextSetupStage = generateShipData;
									end else
									X_operation = keepX;
									Y_operation = subY;
									nextSetupStage = placeShip;
								end
							7: begin
									if((shipCoordX0 > (7 - shipLength)) || (shipCoordY0 < shipLength)) begin
										//if(shipCoordX0 > (7 - shipLength))	shipCoordX0 <= lfsrX;
										//if(shipCoordY0 < shipLength) 			shipCoordY0 <= lfsrY;
										nextSetupStage = generateShipData;
									end else
									X_operation = addX;
									Y_operation = subY;
									nextSetupStage = placeShip;
								end
						endcase
					
							
							//Go IMMEDIATELY into the placeShip state when done
						//nextSetupStage = placeShip;
					end
					
					
					
					placeShip: begin			
						
						//if((shipIndex <= 1) &&(shipIndex >= 0)) 	shipID = 1;
						//if((shipIndex <= 3) &&(shipIndex >= 2)) 	shipID = 2;
						//if((shipIndex <= 6) &&(shipIndex >= 4)) 	shipID = 3;
						//if((shipIndex <= 9) &&(shipIndex >= 7)) 	shipID = 4;
						//if((shipIndex <= 13)&&(shipIndex >= 10)) 	shipID = 5;
						//if((shipIndex <= 17)&&(shipIndex >= 14)) 	shipID = 6;
									
						//initialize shipIndex to start after placing the initial point
						shipIndex = startIndex-1;
					
						//Setting up starting points
						shipX[startIndex] <= shipCoordX0;
						shipY[startIndex] <= shipCoordY0;
						
						//------------------------------BEGIN SETTING ALL OTHER POINTS---------------------------------------------
						
						//for(shipIndex = startIndex-1; shipIndex >= (startIndex - shipLength+1); shipIndex = shipIndex - 1)
						//while(shipIndex >= (startIndex - shipLength + 1))
						for(shipIndex = 16; shipIndex >= 0; shipIndex = shipIndex - 1) begin
							//If we're within our index range for the ship
							if((shipIndex > (startIndex-shipLength+1)) && (shipIndex <= startIndex)) begin
								//Create X coordinates
								case(X_operation)	//create X_operation parameter and every new parameter below
									addX:  shipX[shipIndex] <= shipX[shipIndex+1] + 1;
									subX:  shipX[shipIndex] <= shipX[shipIndex+1] - 1;
									keepX: shipX[shipIndex] <= shipX[shipIndex+1];
								endcase
								//Create Y coordinates
								case(Y_operation)
									addY:  shipY[shipIndex] <= shipY[shipIndex+1] + 1;
									subY:  shipY[shipIndex] <= shipY[shipIndex+1] - 1;
									keepY: shipY[shipIndex] <= shipY[shipIndex+1];
								endcase
								//shipIndex = shipIndex - 1;
							end
						end
						//------------------------------END SETTING ALL OTHER POINTS---------------------------------------------
						
						
						
						//----------------------------BEGIN COLLISION DETECTION------------------------------------------------------
						
						//setting starting index for collisions
						currentIndex 	= startIndex;
						lastIndex		= startIndex-shipLength+1;
						
						//If we are still setting ship 6, then no need to detect collisions
						//No other ships have been set up yet
						if(startIndex == 17) begin
							collisionDetected = 0;
							//shipID = 5;
						end
						
						else begin
							//											(so we dont fall out of the index range)
							//for(currentIndex = startIndex; currentIndex >= lastIndex; currentIndex = currentIndex-1)
							for(currentIndex = 13; currentIndex >= 0; currentIndex = currentIndex-1) begin
								if((currentIndex >= lastIndex) && (currentIndex <= startIndex))
								begin
									//for(comparingIndex = startIndex+1; comparingIndex <= 17; comparingIndex = comparingIndex + 1)
									for(comparingIndex = 0; comparingIndex <= 17; comparingIndex = comparingIndex + 1) begin
										//------------------BEGIN PASSAGE CASE------------------------------------------------------------------
										if((comparingIndex > startIndex) && (comparingIndex <= 17)) begin
											//Overlap Case
											if(
												(shipX[currentIndex] == shipX[comparingIndex])&& 
												(shipY[currentIndex] == shipY[comparingIndex])
												)
											begin
												collisionDetected = 1;
											end
																							
											//BEGIN ---------------------------Side collision Case-----------------------------------------
											else if(
															(currentIndex != lastIndex)
														&&((currentIndex-1)>0)
														&&((comparingIndex+1)<18)
														&&((comparingIndex-1)>0)
													  ) 
											begin
												//Identifying the comparingIndex's Ship
													  if((comparingIndex <= 1) &&(comparingIndex >= 0)) 	
													comparingShipID = 1;
												else if((comparingIndex <= 3) &&(comparingIndex >= 2)) 	
													comparingShipID = 2;
												else if((comparingIndex <= 6) &&(comparingIndex >= 4)) 	
													comparingShipID = 3;
												else if((comparingIndex <= 9) &&(comparingIndex >= 7)) 	
													comparingShipID = 4;
												else if((comparingIndex <= 13)&&(comparingIndex >= 10)) 
													comparingShipID = 5;
												else if((comparingIndex <= 17)&&(comparingIndex >= 14)) 
													comparingShipID = 6;
												
												//-------------------BEGINNING OF SIDE COLLISION DETECTION ALGORITHM
												case(shipDirection) //detects orientation of currentShip
													1: begin
															//is there a point above our current location?
															//Do we have a match for the Y-coordinate above our location
															if((shipY[currentIndex] + 1) == shipY[comparingIndex]) begin
																//do the X-coordinates match?
																if(shipX[currentIndex]    == shipX[comparingIndex]) begin
																	//Look at the next point on our ship (assuming the ship went in direction 7)
																	//Is there a point below it?
																	if(((shipY[currentIndex-1] - 1) == shipY[comparingIndex-1])&& 
																		 (shipX[currentIndex-1]      == shipX[comparingIndex-1]))
																	begin
																		//Identifying each nextComparingShipID here
																		
																			  if(((comparingIndex-1) <= 1) &&((comparingIndex-1) >= 0)) 	
																			nextComparingShipID = 1;
																		else if(((comparingIndex-1) <= 3) &&((comparingIndex-1) >= 2)) 	
																			nextComparingShipID = 2;
																		else if(((comparingIndex-1) <= 6) &&((comparingIndex-1) >= 4)) 	
																			nextComparingShipID = 3;
																		else if(((comparingIndex-1) <= 9) &&((comparingIndex-1) >= 7)) 	
																			nextComparingShipID = 4;
																		else if(((comparingIndex-1) <= 13)&&((comparingIndex-1) >= 10)) 	
																			nextComparingShipID = 5;
																		else if(((comparingIndex-1) <= 17)&&((comparingIndex-1) >= 14)) 	
																			nextComparingShipID = 6;
																		else if((comparingIndex+1) > 17)
																			nextComparingShipID = 0;
																		
																		//if comparingIndex and comparingIndex belong to same ship
																		if(nextComparingShipID == comparingShipID) 
																			collisionDetected = 1;
																		else 
																			collisionDetected = 0;
																	end //End of if statement that assumes direction 7 (comparingIndex-1)
																	
																	//If we had the wrong direction before and the comparing ship was in 
																	//the opposite direction (direction 3)
																	else if(((shipY[currentIndex-1] - 1) == shipY[comparingIndex+1])&&
																				(shipX[currentIndex-1]      == shipX[comparingIndex+1]))
																	begin
																		//Identifying each nextComparingShipID here
																		
																			  if(((comparingIndex+1) <= 1) &&((comparingIndex+1) >= 0)) 	
																			nextComparingShipID = 1;
																		else if(((comparingIndex+1) <= 3) &&((comparingIndex+1) >= 2)) 	
																			nextComparingShipID = 2;
																		else if(((comparingIndex+1) <= 6) &&((comparingIndex+1) >= 4)) 	
																			nextComparingShipID = 3;
																		else if(((comparingIndex+1) <= 9) &&((comparingIndex+1) >= 7)) 	
																			nextComparingShipID = 4;
																		else if(((comparingIndex+1) <= 13)&&((comparingIndex+1) >= 10)) 	
																			nextComparingShipID = 5;
																		else if(((comparingIndex+1) <= 17)&&((comparingIndex+1) >= 14)) 	
																			nextComparingShipID = 6;
																		else if((comparingIndex+1) > 17)
																			nextComparingShipID = 0;
																		
																		//comparing Index and comparingIndex belong to the same ship
																		if(nextComparingShipID == comparingShipID)
																			collisionDetected = 1;
																		else 
																			collisionDetected = 0;
																	end //End of if statement that assumes direction 3 (comparingIndex+1)
																end //End of checking for X-coordinates (if statement)
															end //End of checking for a match for the Y-coordinate above our point
															else begin
																	collisionDetected = 0;
															end
														end //End of Case 1	
														
													3: begin
															//is there a point above our current location?
															//Do we have a match for the Y-coordinate above our location?
															if((shipY[currentIndex] + 1) == shipY[comparingIndex])
															begin
																//do the X-coordinates match?
																if(shipX[currentIndex]    == shipX[comparingIndex]) 
																begin
																	//Look at the next point on our ship (assuming the ship went in direction 5)
																	//Is there a point below it?
																	if(((shipY[currentIndex-1] - 1) == shipY[comparingIndex-1])&& 
																		 (shipX[currentIndex-1]      == shipX[comparingIndex-1]))
																	begin
																		//Identifying each nextComparingShipID here
																		
																			  if(((comparingIndex-1) <= 1) &&((comparingIndex-1) >= 0)) 	
																			nextComparingShipID = 1;
																		else if(((comparingIndex-1) <= 3) &&((comparingIndex-1) >= 2)) 	
																			nextComparingShipID = 2;
																		else if(((comparingIndex-1) <= 6) &&((comparingIndex-1) >= 4)) 	
																			nextComparingShipID = 3;
																		else if(((comparingIndex-1) <= 9) &&((comparingIndex-1) >= 7)) 	
																			nextComparingShipID = 4;
																		else if(((comparingIndex-1) <= 13)&&((comparingIndex-1) >= 10)) 	
																			nextComparingShipID = 5;
																		else if(((comparingIndex-1) <= 17)&&((comparingIndex-1) >= 14)) 	
																			nextComparingShipID = 6;
																		else if((comparingIndex+1) > 17)
																			nextComparingShipID = 0;
																		
																		//if comparingIndex and comparingIndex belong to same ship
																		if(nextComparingShipID == comparingShipID) 
																			collisionDetected = 1;
																		else 
																			collisionDetected = 0;
																	end //End of if statement that assumes direction 5 (comparingIndex-1)
																	
																	//If we had the wrong direction before and the comparing ship was in 
																	//the opposite direction (direction 1)
																	else if(((shipY[currentIndex-1] - 1) == shipY[comparingIndex+1])&&
																				(shipX[currentIndex-1]      == shipX[comparingIndex+1]))
																	begin
																		//Identifying each nextComparingShipID here
																		
																			  if(((comparingIndex+1) <= 1) &&((comparingIndex+1) >= 0)) 	
																			nextComparingShipID = 1;
																		else if(((comparingIndex+1) <= 3) &&((comparingIndex+1) >= 2)) 	
																			nextComparingShipID = 2;
																		else if(((comparingIndex+1) <= 6) &&((comparingIndex+1) >= 4)) 	
																			nextComparingShipID = 3;
																		else if(((comparingIndex+1) <= 9) &&((comparingIndex+1) >= 7)) 	
																			nextComparingShipID = 4;
																		else if(((comparingIndex+1) <= 13)&&((comparingIndex+1) >= 10)) 	
																			nextComparingShipID = 5;
																		else if(((comparingIndex+1) <= 17)&&((comparingIndex+1) >= 14)) 	
																			nextComparingShipID = 6;
																		else if((comparingIndex+1) > 17)
																			nextComparingShipID = 0;
																		
																		//comparing Index and comparingIndex belong to the same ship
																		if(nextComparingShipID == comparingShipID)
																			collisionDetected = 1;
																		else 
																			collisionDetected = 0;
																	end //End of if statement that assumes direction 1 (comparingIndex+1)
																end //End of checking for X-coordinates (if statement)
															end //End of checking for a match for the Y-coordinate above our point
															else begin
																	collisionDetected = 0;
															end
														end //End of Case 3
													
													5: begin
															//is there a point below our current location?
															//Do we have a match for the Y-coordinate below our location?
															if((shipY[currentIndex] - 1) == shipY[comparingIndex]) begin
																//do the X-coordinates match?
																if(shipX[currentIndex]    == shipX[comparingIndex]) begin
																	//Look at the next point on our ship (assuming the comparing ship went in direction 3)
																	//Is there a point above it?
																	if(((shipY[currentIndex-1] + 1) == shipY[comparingIndex-1])&& 
																		 (shipX[currentIndex-1]      == shipX[comparingIndex-1]))
																	begin
																		//Identifying each nextComparingShipID here
																		
																			  if(((comparingIndex-1) <= 1) &&((comparingIndex-1) >= 0)) 	
																			nextComparingShipID = 1;
																		else if(((comparingIndex-1) <= 3) &&((comparingIndex-1) >= 2)) 	
																			nextComparingShipID = 2;
																		else if(((comparingIndex-1) <= 6) &&((comparingIndex-1) >= 4)) 	
																			nextComparingShipID = 3;
																		else if(((comparingIndex-1) <= 9) &&((comparingIndex-1) >= 7)) 	
																			nextComparingShipID = 4;
																		else if(((comparingIndex-1) <= 13)&&((comparingIndex-1) >= 10)) 	
																			nextComparingShipID = 5;
																		else if(((comparingIndex-1) <= 17)&&((comparingIndex-1) >= 14)) 	
																			nextComparingShipID = 6;
																		else if((comparingIndex+1) > 17)
																			nextComparingShipID = 0;
																		
																		//if comparingIndex and comparingIndex belong to same ship
																		if(nextComparingShipID == comparingShipID) 
																			collisionDetected = 1;
																		else 
																			collisionDetected = 0;
																	end //End of if statement that assumes direction 3 (comparingIndex-1)
																	
																	//If we had the wrong direction before and the comparing ship was in 
																	//the opposite direction (direction 7 now)
																	//Difference between 1 and 3: shipY[currentIndex-1] + 1 
																	//We look at position above the next point
																	//This coordinate system is backwards, in that the next coordinates are at
																	//lower indices
																	else if(((shipY[currentIndex-1] + 1) == shipY[comparingIndex+1])&&
																				(shipX[currentIndex-1]      == shipX[comparingIndex+1]))
																	begin
																		//Identifying each nextComparingShipID here
																		
																			  if(((comparingIndex+1) <= 1) &&((comparingIndex+1) >= 0)) 	
																			nextComparingShipID = 1;
																		else if(((comparingIndex+1) <= 3) &&((comparingIndex+1) >= 2)) 	
																			nextComparingShipID = 2;
																		else if(((comparingIndex+1) <= 6) &&((comparingIndex+1) >= 4)) 	
																			nextComparingShipID = 3;
																		else if(((comparingIndex+1) <= 9) &&((comparingIndex+1) >= 7)) 	
																			nextComparingShipID = 4;
																		else if(((comparingIndex+1) <= 13)&&((comparingIndex+1) >= 10)) 	
																			nextComparingShipID = 5;
																		else if(((comparingIndex+1) <= 17)&&((comparingIndex+1) >= 14)) 	
																			nextComparingShipID = 6;
																		else if((comparingIndex+1) > 17)
																			nextComparingShipID = 0;
																		
																		//comparing Index and comparingIndex belong to the same ship
																		if(nextComparingShipID == comparingShipID)
																			collisionDetected = 1;
																		else 
																			collisionDetected = 0;
																	end //End of if statement that assumes direction 7 (comparingIndex+1)
																end //End of checking for X-coordinates (if statement)
															end //End of checking for a match for the Y-coordinate below our point
															else begin
																	collisionDetected = 0;
															end
														end //End of Case 5
														
													7: begin
															//is there a point below our current location?
															//Do we have a match for the Y-coordinate below our location?
															if((shipY[currentIndex] - 1) == shipY[comparingIndex]) begin
																//do the X-coordinates match?
																if(shipX[currentIndex]    == shipX[comparingIndex]) begin
																	//Look at the next point on our ship (assuming the ship went in direction 1)
																	//Is there a point above it?
																	//Difference between 1 and 3: shipY[currentIndex-1] + 1 
																	//We look at position above the next point
																	if(((shipY[currentIndex-1] + 1) == shipY[comparingIndex-1])&& 
																		 (shipX[currentIndex-1]      == shipX[comparingIndex-1]))
																	begin
																		//Identifying each nextComparingShipID here
																		
																			  if(((comparingIndex-1) <= 1) &&((comparingIndex-1) >= 0)) 	
																			nextComparingShipID = 1;
																		else if(((comparingIndex-1) <= 3) &&((comparingIndex-1) >= 2)) 	
																			nextComparingShipID = 2;
																		else if(((comparingIndex-1) <= 6) &&((comparingIndex-1) >= 4)) 	
																			nextComparingShipID = 3;
																		else if(((comparingIndex-1) <= 9) &&((comparingIndex-1) >= 7)) 	
																			nextComparingShipID = 4;
																		else if(((comparingIndex-1) <= 13)&&((comparingIndex-1) >= 10)) 	
																			nextComparingShipID = 5;
																		else if(((comparingIndex-1) <= 17)&&((comparingIndex-1) >= 14)) 	
																			nextComparingShipID = 6;
																		else if((comparingIndex+1) > 17)
																			nextComparingShipID = 0;
																			
																		
																		//if comparingIndex and comparingIndex belong to same ship
																		if(nextComparingShipID == comparingShipID) 
																			collisionDetected = 1;
																		else 
																			collisionDetected = 0;
																	end //End of if statement that assumes direction 1 (comparingIndex-1)
																	
																	//If we had the wrong direction before and the comparing ship was in 
																	//the opposite direction (direction 5)
																	//Difference between 1 and 3, and 7: shipY[currentIndex-1] + 1 
																	//We look at position above the next point
																	else if(((shipY[currentIndex-1] + 1) == shipY[comparingIndex+1])&&
																				(shipX[currentIndex-1]      == shipX[comparingIndex+1]))
																	begin
																		//Identifying each nextComparingShipID here
																		
																			  if(((comparingIndex+1) <= 1) &&((comparingIndex+1) >= 0)) 	
																			nextComparingShipID = 1;
																		else if(((comparingIndex+1) <= 3) &&((comparingIndex+1) >= 2)) 	
																			nextComparingShipID = 2;
																		else if(((comparingIndex+1) <= 6) &&((comparingIndex+1) >= 4)) 	
																			nextComparingShipID = 3;
																		else if(((comparingIndex+1) <= 9) &&((comparingIndex+1) >= 7)) 	
																			nextComparingShipID = 4;
																		else if(((comparingIndex+1) <= 13)&&((comparingIndex+1) >= 10)) 	
																			nextComparingShipID = 5;
																		else if(((comparingIndex+1) <= 17)&&((comparingIndex+1) >= 14)) 	
																			nextComparingShipID = 6;
																		else if((comparingIndex+1) > 17)
																			nextComparingShipID = 0;
																		
																		//comparing Index and comparingIndex belong to the same ship
																		if(nextComparingShipID == comparingShipID)
																			collisionDetected = 1;
																		else 
																			collisionDetected = 0;
																	end //End of if statement that assumes direction 5 (comparingIndex+1)
																end //End of checking for X-coordinates (if statement)
															end //End of checking for a match for the Y-coordinate below our point
															else begin
																	collisionDetected = 0;
															end
														end //End of Case 7
												endcase	
												//--------------------------END OF SIDE COLLISION DETECTION ALGORITHM
												
												
											end 
											//END of evaluating whether each point before the last is going to collide with a ship
											//--------END OF BOTH BOTH SIDE COLLISION AND OVERLAP CASES---------------------------------
											else begin
												//if it's the last point, and no collisions detected, set collisionDetected to 0
												collisionDetected = 0;
											end	
										end
										//-------------------END OF PASSAGE CASE-----------------------------------------------------
									end
									//----------------------END OF INNER FOR LOOP (iterating through the comparingShip positions)
								end
							end
							//-------------------------END OF OUTER FOR LOOP (iterating through the currentShip positions)
						end
						//----------------------------END COLLISION DETECTION------------------------------------------------------
						if(collisionDetected == 0) begin
							case(shipID)
								6: shipID = 5;
								5: shipID = 4;
								4: shipID = 3;
								3: shipID = 3;
								2: shipID = 1;
								1: begin
										//shipID = 6;
										Y = playMode;
										W = 1;
									end
							endcase
						end else begin
							//getDir = 1;
							nextSetupStage = generateShipData;//generateDirection; //start the process over with new coordinates and a new direction
						end
					end //END placeShip Case 	- Begins line 486
					
					default: nextSetupStage = generateShipData;//generateDirection;
				endcase//END nextSetupStage cases - Begins line 368
				
			end		 //END setupMode Stage 	- Begins line 324
			
		endcase//*********************************END MAIN case statment (begins line 207)***************************************************************
		
		//Display everything to the 7-segments
		dispHEX0 <= dispHEX[0];
		dispHEX1 <= dispHEX[1];
		dispHEX2 <= dispHEX[2];
		dispHEX3 <= dispHEX[3];
		
	end//end always statement
endmodule
