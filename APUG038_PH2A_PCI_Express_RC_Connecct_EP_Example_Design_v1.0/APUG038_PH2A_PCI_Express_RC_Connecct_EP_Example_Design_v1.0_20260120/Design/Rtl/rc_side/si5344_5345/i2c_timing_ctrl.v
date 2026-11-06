`timescale 1ns/1ns
//********************************************************************** 
// -------------------------------------------------------------------
// >>>>>>>>>>>>>>>>>>>>>>>Copyright Notice<<<<<<<<<<<<<<<<<<<<<<<<<<<< 
// ------------------------------------------------------------------- 
//             /\ --------------- 
//            /  \ ------------- 
//           / /\ \ -----------
//          / /  \ \ ---------
//         / /    \ \ ------- 
//        / /      \ \ ----- 
//       / /_ _ _   \ \ --- 
//      /_ _ _ _ _\  \_\ -
//*********************************************************************** 
// Author: suluyang 
// Email:luyang.su@anlogic.com 
// Date:2020/04/21 
// Description: 
// 
// 
// 
// 
// web：www.anlogic.com 
//------------------------------------------------------------------- 
//*********************************************************************/
module	i2c_timing_ctrl
#(
	parameter	CLK_FREQ	=	100_000_000,	//100 MHz
	parameter	I2C_ADDR_BYTE=	0,//0-> 1byte  1->2byte
	parameter	I2C_FREQ	=	100_000		//10 KHz(< 400KHz)
)
(
	//global clock
	input	clk,		//100MHz
	input	rst_n,		//system reset
	
	//i2c interface
	output	i2c_sclk,	//i2c clock
	inout	i2c_sdat,	//i2c data for bidirection

	//user interface
	input		[9:0]	i2c_config_size,	//i2c config data counte
	output	reg	[9:0]	i2c_config_index,	//i2c config reg index, read 2 reg and write xx reg
	input		[31:0]	i2c_config_data,	//i2c config data
	output				i2c_config_done 
);


reg add_cnt_en;
reg	[4:0]	RESETn=5'd31;
reg	[16:0]	delay_cnt;
localparam	DELAY_TOP = CLK_FREQ/250;	//1ms Setting time after software/hardware reset
reg	[23:0]	delay_300m_cnt;
reg delay_300m_start;
reg delay_300m_ok;
localparam	DELAY_300M = 7500000;	//300ms Setting time after software/hardware reset
reg [7:0] cnt;
wire      end_cnt;
wire      add_cnt;
reg	[15:0]	clk_cnt;	//divide for i2c clock
reg	i2c_ctrl_clk;		//i2c control clock, H: valid; L: valid
reg	i2c_transfer_en;	//send i2c data	before, make sure that sdat is steady when i2c_sclk is valid
reg	i2c_capture_en;		//capture i2c data	while sdat is steady from cmos 		
//-----------------------------------------
//I2C Timing state Parameter
localparam	I2C_IDLE		=	5'd0;
//Write I2C: {ID_Address, REG_Address+REG_Address2, W_REG_Data}
localparam	I2C_WR_START	=	5'd1;
localparam	I2C_WR_IDADDR	=	5'd2;
localparam	I2C_WR_ACK1		=	5'd3;
localparam	I2C_WR_REGADDR	=	5'd4;
localparam	I2C_WR_ACK2	    =	5'd5;
localparam	I2C_WR_REGADDR2	=	5'd6;
localparam	I2C_WR_ACK2A    =	5'd7;
localparam	I2C_WR_REGDATA	=	5'd8;
localparam	I2C_WR_ACK3		=	5'd9;
localparam	I2C_WR_STOP		=	5'd10;
//reg	i2c_write_flag,  
reg	i2c_sdat_out;		//i2c data output
reg	[7:0]	i2c_wdata;	//i2c data prepared to transfer
reg	i2c_ack1, i2c_ack2, i2c_ack3,i2c_ack2a;

wire i2c_sdat_in;
//reg	i2c_ack;
//reg	[7:0]	i2c_rdata;
reg i2c_sdat_reg;
reg cnt_en;
reg	[3:0]	i2c_stream_cnt;	//i2c data bit stream count
reg clk_en;
reg bir_en;
wire tri_en;
reg	[4:0]	current_state, next_state; //i2c write and read state  
wire	i2c_transfer_end;
reg i2c_transfer_end_en;

//MMMMMMMMM	复位信号同步化	MMMMMMMMM

always@(posedge clk)//
	RESETn	<={RESETn[3:0],rst_n};//最终使用的同步信号是RESETn[4]

//----------------------------------------
//Delay xxus until i2c slave is steady


always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		delay_cnt <= 0;
	else if(delay_cnt < DELAY_TOP)
		delay_cnt <= delay_cnt + 1'b1;
	else
		delay_cnt <= delay_cnt;
end
wire delay_done = (delay_cnt == DELAY_TOP) ? 1'b1 : 1'b0;	//81us delay

//------------------------------------------

always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		delay_300m_cnt <= 0;
	else if(delay_300m_start)
		if(delay_300m_cnt < DELAY_300M)
			delay_300m_cnt <= delay_300m_cnt + 1'b1;
		else
			delay_300m_cnt <= delay_300m_cnt;
end
wire delay_300m_done = (delay_300m_cnt == DELAY_300M) ? 1'b1 : 1'b0;

//------------------------------------------

//计数器1
 always @(posedge clk or negedge rst_n)begin
     if(!rst_n)begin
         cnt <= 0;
     end
     else if(add_cnt)begin
         if(end_cnt)
             cnt <= 0;
         else
             cnt <= cnt + 1;
     end
	 else
		cnt <= 0; 
 end
 

 assign add_cnt = add_cnt_en;       
 assign end_cnt = add_cnt && cnt == 250; 
 

always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		add_cnt_en <= 0;
	else if(current_state == I2C_WR_START )
		add_cnt_en <= 1;
	else
		add_cnt_en <= 0;
end
 

//----------------------------------------
//I2C Control Clock generate

/******************************************
			 _______		  _______
SCLK	____|		|________|		 |
		 ________________ ______________
SDAT	|________________|______________
		 _	              _
CLK_EN	| |______________| |____________
			    _			  	 _
CAP_EN	_______| |______________| |_____
*******************************************/
		
always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		begin
		clk_cnt <= 0;
		i2c_ctrl_clk <= 0;
		i2c_transfer_en <= 0;
		i2c_capture_en <= 0;
		end
	else if(delay_done&&delay_300m_ok || delay_300m_done)
		begin
		if(clk_cnt < (CLK_FREQ/I2C_FREQ) - 1'b1)
			clk_cnt <= clk_cnt + 1'd1;
		else
			clk_cnt <= 0;
			
		//i2c control clock, H: valid; L: valid
		i2c_ctrl_clk <= ((clk_cnt >= (CLK_FREQ/I2C_FREQ)/4 + 1'b1) &&
						(clk_cnt < (3*CLK_FREQ/I2C_FREQ)/4 + 1'b1)) ? 1'b1 : 1'b0;
		//send i2c data	before, make sure that sdat is steady when i2c_sclk is valid
		i2c_transfer_en <= (clk_cnt == 16'd0) ? 1'b1 : 1'b0;
		//capture i2c data	while sdat is steady from cmos 					
		i2c_capture_en <= (clk_cnt == (2*CLK_FREQ/I2C_FREQ)/4 - 1'b1) ? 1'b1 : 1'b0;
		end
	else
		begin
		clk_cnt <= 0;
		i2c_ctrl_clk <= 0;
		i2c_transfer_en <= 0;
		i2c_capture_en <= 0;
		end
end



//-----------------------------------------
// FSM: always1

always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		current_state <= I2C_IDLE;
	else if(i2c_transfer_en)
		current_state <= next_state;
end

//-----------------------------------------

assign i2c_transfer_end = i2c_transfer_end_en;

always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		i2c_transfer_end_en <= 0;
	else if(current_state == I2C_WR_STOP )
		i2c_transfer_end_en <= 1;
	else
		i2c_transfer_end_en <= 0;
end

reg		i2c_ack;	//i2c slave renpose successed
always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])begin
		i2c_config_index <= 0;
		delay_300m_start <= 0;
		delay_300m_ok    <= 1;
	end	
	else if(i2c_transfer_en)
		begin
		// if(i2c_transfer_end && ~i2c_ack)
		if(i2c_transfer_end)		
		begin
			if(i2c_config_index < i2c_config_size)begin	
				if(delay_300m_done || i2c_config_index < 5)begin
					i2c_config_index <= i2c_config_index + 1'b1;
					delay_300m_start <= 0;
					delay_300m_ok    <= 1;
				end
				if(i2c_config_index == 5)begin
					delay_300m_start <= 1;
					delay_300m_ok    <= 0;
				end									
			end	
			else begin
				i2c_config_index <= i2c_config_size;
			end	
		end
		else
			i2c_config_index <= i2c_config_index;
		end
	else
		i2c_config_index <= i2c_config_index;
end

assign	i2c_config_done = (i2c_config_index == i2c_config_size) ? 1'b1 : 1'b0;

//-----------------------------------------
// FSM: always2

always@(*)
begin
	next_state = I2C_IDLE; 	//state initialization
	case(current_state)
	I2C_IDLE:		//5'd0
		begin
		if(delay_done&&delay_300m_ok || delay_300m_done)	//1ms Setting time after software/hardware reset	
			begin
			if(i2c_transfer_en)
				begin
                if(i2c_config_index < i2c_config_size)
					next_state = I2C_WR_START;	//Write Data to I2C
				else
					next_state = I2C_IDLE;		//Config I2C Complete
				end
			else
				next_state = next_state;
			end
		else
				next_state = I2C_IDLE;		//Wait I2C Bus is steady
		end
	//Write I2C: {ID_Address, REG_Address, W_REG_Data}
	I2C_WR_START:	//5'd1
		begin
		if(i2c_transfer_en)	next_state = I2C_WR_IDADDR;
		else				next_state = I2C_WR_START;
		end
	I2C_WR_IDADDR:	//5'd2
		if(i2c_transfer_en == 1'b1 && i2c_stream_cnt == 4'd8)	
							next_state = I2C_WR_ACK1;
		else				next_state = I2C_WR_IDADDR;
	I2C_WR_ACK1:	//5'd3
		// if(i2c_transfer_en && !i2c_ack1)
		if(i2c_transfer_en )		
			if(I2C_ADDR_BYTE)
				next_state = I2C_WR_REGADDR;
			else
				next_state = I2C_WR_REGADDR2;
		else				
			next_state = I2C_WR_ACK1;
		
	I2C_WR_REGADDR:	//5'd4
		if(i2c_transfer_en == 1'b1 && i2c_stream_cnt == 4'd8)	
							next_state = I2C_WR_ACK2;
		else				next_state = I2C_WR_REGADDR;
	I2C_WR_ACK2:	//5'd5
		if(i2c_transfer_en)	next_state = I2C_WR_REGADDR2;
		else				next_state = I2C_WR_ACK2;
	I2C_WR_REGADDR2:	//5'd6
		if(i2c_transfer_en == 1'b1 && i2c_stream_cnt == 4'd8)	
							next_state = I2C_WR_ACK2A;
		else				next_state = I2C_WR_REGADDR2;
	I2C_WR_ACK2A:	//5'd7
		if(i2c_transfer_en)	next_state = I2C_WR_REGDATA;
		else				next_state = I2C_WR_ACK2A;		
	I2C_WR_REGDATA:	//5'd8
		if(i2c_transfer_en == 1'b1 && i2c_stream_cnt == 4'd8)	
							next_state = I2C_WR_ACK3;
		else				next_state = I2C_WR_REGDATA;
	I2C_WR_ACK3:	//5'd9
		if(i2c_transfer_en)	next_state = I2C_WR_STOP;
		else				next_state = I2C_WR_ACK3;
	I2C_WR_STOP:	//5'd10
		if(i2c_transfer_en)	next_state = I2C_IDLE;
		else				next_state = I2C_WR_STOP;
	default:;	//default vaule		
	endcase
end

//-----------------------------------------
// FSM: always3


always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		begin
		i2c_sdat_out <= 1'b1;
		i2c_stream_cnt <= 0;
		i2c_wdata <= 0;
		end
	else if(i2c_transfer_en)
		begin
		case(next_state)
		I2C_IDLE:	//5'd0
			begin
			i2c_sdat_out <= 1'b1;		//idle state
			i2c_stream_cnt <= 0;
			i2c_wdata <= 0;
			end
		//Write I2C: {ID_Address, REG_Address, W_REG_Data}
		I2C_WR_START:	//5'd1
			begin
			i2c_sdat_out <= 1'b0;
			i2c_stream_cnt <= 0;
			i2c_wdata <= i2c_config_data[31:24];	//ID_Address		
			end
		I2C_WR_IDADDR:	//5'd2
			begin
			i2c_stream_cnt <= i2c_stream_cnt + 1'b1;
			i2c_sdat_out <= i2c_wdata[3'd7 - i2c_stream_cnt];
			end
		I2C_WR_ACK1:	//5'd3
			begin
			i2c_stream_cnt <= 0;
			i2c_sdat_out <= 1'b0;
			if(I2C_ADDR_BYTE)
				i2c_wdata <= i2c_config_data[23:16];		//REG_Address
			else
				i2c_wdata <= i2c_config_data[15:8];		//REG_Address		
			end
		I2C_WR_REGADDR:	//5'd4
			begin
			i2c_stream_cnt <= i2c_stream_cnt + 1'b1;
			i2c_sdat_out <= i2c_wdata[3'd7 - i2c_stream_cnt];
			end
		I2C_WR_ACK2:	//5'd5
			begin
			i2c_sdat_out <= 1'b0;
			i2c_stream_cnt <= 0;
			i2c_wdata <= i2c_config_data[15:8];		//REG_Address	
			end
		I2C_WR_REGADDR2:	//5'd6
			begin
			i2c_stream_cnt <= i2c_stream_cnt + 1'b1;
			i2c_sdat_out <= i2c_wdata[3'd7 - i2c_stream_cnt];
			end
		I2C_WR_ACK2A:	//5'd7
			begin
			i2c_sdat_out <= 1'b0;
			i2c_stream_cnt <= 0;
			i2c_wdata <= i2c_config_data[7:0];		//W_REG_Data		
			end			
		I2C_WR_REGDATA:	//5'd8
			begin
			i2c_stream_cnt <= i2c_stream_cnt + 1'b1;
			i2c_sdat_out <= i2c_wdata[3'd7 - i2c_stream_cnt];
			end
		I2C_WR_ACK3:	//5'd9
			begin
			i2c_sdat_out <= 1'b0;
			i2c_stream_cnt <= 0;
			end	
		I2C_WR_STOP:	//5'd10
			begin
			i2c_sdat_out <= 1'b0;
			end	
		default:
            begin
            i2c_sdat_out <= 1'b1;
            i2c_stream_cnt <= 0;
            i2c_wdata <= 0;
            end
		endcase
		end
	else
		begin
		i2c_stream_cnt <= i2c_stream_cnt;
		i2c_sdat_out <= i2c_sdat_out;
		end
end

//---------------------------------------------
//respone from slave for i2c data transfer

always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		begin
		{i2c_ack1, i2c_ack2, i2c_ack3,i2c_ack2a} <= 4'b1111;
		i2c_ack <= 1'b1;
		end
	else if(i2c_capture_en)	
		begin
		case(next_state)
		I2C_IDLE:
			begin
		{i2c_ack1, i2c_ack2, i2c_ack3,i2c_ack2a} <= 4'b1111;
		i2c_ack <= 1'b1;
			end
		//Write I2C: {ID_Address, REG_Address, W_REG_Data}
		I2C_WR_ACK1:	i2c_ack1  <= i2c_sdat_in;
		I2C_WR_ACK2:	i2c_ack2  <= i2c_sdat_in;
		I2C_WR_ACK2A:	i2c_ack2a <= i2c_sdat_in;		
		I2C_WR_ACK3:	i2c_ack3  <= i2c_sdat_in;
		I2C_WR_STOP:
			begin
				if(I2C_ADDR_BYTE)
					i2c_ack <= (i2c_ack1 | i2c_ack2 | i2c_ack3 | i2c_ack2a);
				else
					i2c_ack <= (i2c_ack1 | i2c_ack3 | i2c_ack2a);
			end
		endcase
		end
	else
		begin
		{i2c_ack1, i2c_ack2, i2c_ack3,i2c_ack2a} <= {i2c_ack1, i2c_ack2, i2c_ack3,i2c_ack2a};
		i2c_ack <= i2c_ack;
		end
end


always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		i2c_sdat_reg <= 1;
	else if(bir_en)
		i2c_sdat_reg <= i2c_sdat_in;
	else 
		i2c_sdat_reg <= 1;		
end


always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		cnt_en <= 0;
	else if(current_state >= 2 && current_state <= 8 )
		cnt_en <= 1;
	else
		cnt_en <= 0;
end

//---------------------------------------------------
// wire	bir_en =   (current_state == I2C_WR_ACK1 || current_state == I2C_WR_ACK2 || 
                     // current_state == I2C_WR_ACK2A ||current_state == I2C_WR_ACK3 || i2c_sdat_cnt == 8 || i2c_sdat_cnt == 17 || i2c_sdat_cnt == 26) ? 1'b1 : 1'b0;
//assign	i2c_sclk = clk_en ?i2c_ctrl_clk : 1'b1;
// assign	i2c_sdat = (~bir_en) ? i2c_sdat_out : 1'bz;


always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		clk_en <= 0;
	else if (current_state >= I2C_WR_IDADDR && current_state <= I2C_WR_ACK3 || cnt >= 187)
		clk_en <= 1;
	else
		clk_en <= 0;
end

// reg [5:0]i2c_sdat_cnt;
// always@(negedge i2c_ctrl_clk)
// begin
	// if(!RESETn[4])
		// i2c_sdat_cnt <= 0;
	// else if(cnt_en)
		// i2c_sdat_cnt <= i2c_sdat_cnt + 1;
	// else
		// i2c_sdat_cnt <= 0;
// end


always@(posedge clk or negedge RESETn[4])
begin
	if(!RESETn[4])
		bir_en <= 1;
	else if (current_state == I2C_WR_ACK1 || current_state == I2C_WR_ACK2 || current_state == I2C_WR_ACK2A ||current_state == I2C_WR_ACK3 )
	// else if (current_state == I2C_WR_ACK1 || current_state == I2C_WR_ACK2 || current_state == I2C_WR_ACK2A 
	// ||current_state == I2C_WR_ACK3 || i2c_sdat_cnt == 8 || i2c_sdat_cnt == 17 || i2c_sdat_cnt == 26)
		bir_en <= 1;
	else
		bir_en <= 0;
end


assign tri_en = bir_en;

assign	i2c_sclk = clk_en ?i2c_ctrl_clk : 1'b1;
assign	i2c_sdat = (~bir_en) ? i2c_sdat_out : 1'bz;
assign  i2c_sdat_in = i2c_sdat;

endmodule
