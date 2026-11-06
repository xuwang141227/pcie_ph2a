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
// si5342 频率输出可调，out0 62.5   100   125 MHZ
// 						out1 125    125   100 MHZ
// web：www.anlogic.com 
//------------------------------------------------------------------- 
//*********************************************************************/



module si5344_si5345
#(
	parameter	CLK_FREQ		=	50_000_000,//25 MHz
	parameter	I2C_ADDR_BYTE	=	0,			//0-> 1byte  1->2byte
	parameter	I2C_FREQ		=	100_000		//10 KHz(< 400KHz)
	
)
(
//
	input  wire 	    sys_clk,	//25MHZ
//	input  wire 	    key_rst_n,	//
//	
	output  wire 	    i2c_config_done,//配置指示信号，配置完成拉高电平
//测试指示信号	
	input  wire 	    key,
	output wire[3:0]	led,
//si5342 i/o	
	input 				intrb_n,//	
	output	wire		rstb_n, //POR
	output	wire		IIC_SEL,//
	output	wire		SDO_A0, //	
	output	wire		CSB_A1, //
	output	wire		OEB,    //
	output 				sck_o,  //	
	inout  				sda_io  //
);
localparam	I2C_S_Address	=	8'b11010000;	
	
wire	[9:0]	 i2c_config_index;
wire    [23:0]   i2c_config_data;
wire    [9:0]    i2c_config_size;      
wire             rst_n;
wire 			 key_pulse;

assign		IIC_SEL	= 1;
assign		SDO_A0	= 0;	
assign		CSB_A1	= 0;
assign		OEB	    = 0;



//测试指示灯
assign led[0]=~i2c_config_done;
assign led[1]=~intrb_n;	
assign led[2]=key;
assign led[3]=~rst_n;

debounce	u_debounce(
	.clk		(sys_clk	),
	.rst_n		(rst_n		),
	.key		(key		),
	.key_pulse	(key_pulse	)
);

//-----------------------------------------------------------       
//初始化复位模块
//----------------------------------------------------------- 
count_rst_n#
(
	.num 		(16'hffff			)//2.6ms
)u1_count_rst_n
(
	.clk_i		(sys_clk			),
	.rst_o		(rst_n				),
	.rstb_n		(rstb_n				)
);

//-----------------------------------------------------------       
//i2c时序模块
//-----------------------------------------------------------  
i2c_timing_ctrl
#(
	.CLK_FREQ	(25_000_000),	
	.I2C_FREQ	(100_000)		 
)
u_i2c_timing_ctrl
(
	.clk				(sys_clk				),
	.rst_n				(rst_n           	    ),
	.i2c_sclk			(sck_o					),	
	.i2c_sdat			(sda_io					),
	.i2c_config_index	(i2c_config_index		),	        //i2c config reg index, read reg and write xx reg
	.i2c_config_data	({I2C_S_Address,i2c_config_data}),	//i2c config data
	.i2c_config_size	(i2c_config_size		),	        //i2c config data counte
	.i2c_config_done	(i2c_config_done		)	        //i2c config timing complete
);
//-----------------------------------------------------------       
//si5344初始化配置模块
//-----------------------------------------------------------      

       	I2C_Reg_5344_Config_100Mhz_ALL u1_Config
        (
	        .LUT_INDEX		(i2c_config_index),
	        .LUT_DATA		(i2c_config_data),
	        .LUT_SIZE		(i2c_config_size)
        );





endmodule
 
 
