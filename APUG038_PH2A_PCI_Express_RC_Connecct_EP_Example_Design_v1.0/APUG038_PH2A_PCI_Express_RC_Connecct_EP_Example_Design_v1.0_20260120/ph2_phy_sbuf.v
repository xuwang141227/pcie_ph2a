//------------------------------------------------------------------------------
//  Copyright (c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//------------------------------------------------------------------------------

////////////////////////////////////////////////////////////////////////////////
//
//  Vendor      : Anlogic
//  Version     : 0.5
//  Description : Anlogic Functional Simualtion Model for Physical IP
//				  PH2_PHY_SBUF
//  Filename    : ph2_phy_sbuf.v
//
////////////////////////////////////////////////////////////////////////////////
//
//  Revision    :
//  2024-11-28 - 0.6 - WY.LIU  - Add specify for SWDEV-3187
//  2023-04-03 - 0.5 - GS.JI   - 1.Modify the BYPASS parameter to CE_BYPASS.
//                               2.Modify the GSR parameter default value to DISABLE.
//                               3.Modify the CE_BYPASS parameter default value to ENABLE.
//  2023-03-13 - 0.4 - XT.XUE  - Add USRCLKINV parameter and change rclk assignment.
//  2023-01-03 - 0.3 - GS.JI   - Change BYPASS default values
//  2022-11-05 - 0.2 - GS.JI   - Update the file header.
//  2022-03-09 - 0.1 - YF.MENG - Initial version.
//
////////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps
module PH2_PHY_SBUF (
    ce ,
    clkin ,
    clkout
);

 input ce ;                           //                    [template: Ce Input]
 input clkin ;                        //[tag:clk]           [template: Clk Input]
 output clkout;                       //[tag:clk]           [template: Clk Output]
 parameter GSR = "DISABLE";           //"ENABLE", "DISABLE" [template: Gsr Enable Control]
 parameter CE_BYPASS = "ENABLE";      //"ENABLE", "DISABLE" [template: Ce Bypass Enable Control]
 parameter USRCLKINV  = "SIG";        //"SIG", "INV"        [template: Clk Input Control By User]
 parameter CEINV  = "SIG";            //"SIG", "INV"        [template: Ce Input Control]
 parameter RSTMODE= "ASYNC" ;         //"SYNC", "ASYNC"     [template: Rst Mode Control]

 localparam CLKINV  = "SIG";          //"SIG", "INV"        [template: Clk Input Control] 

`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
2EQfxHmNhh8PdGs+4b8RzBf68Ib6O/F/nEWQ6kqHtee7vz/GLZaFfHTLI+JcbAm4
kl2pRo0S9TUkw+rf51Ky8lZ2+AK/3E63Sw3uIYyf+mcRjU4DwePXoP9fc3BCeA5z
4PJVH5ap1ES5Aq5TEDCbtsBjkjA68REXOhICzdqYEEI=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
m5oNx39g3AZhH4g66aa5aR37onQARwzsD1er9sJuH6gi4fwKZuKGwiJMfx3k8XaS
4EqLHYBzZc/TgMxKWYG+Q+oGRy5cfd9gMP+HxYlEjPm1b0OQ9zmv3QxvYqZltOHm
Ll4voQCRJAz8fLtPZ2lJsZQKmo88G9UvPzKccN0/PF4=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
lTlGXxFnLxkDyq4R+oiZozzC0miXIllJ85Opwdi386Zou8ED+OXZW1WDWN+a55bt
LI4GCsGGEk+NCKEj8xj4McqjZ9Ox9te8NPVVeoSdc5UK8nr/ULwWqrkS/P6f1Uc5
81GQXiN7f5Nxsqgc5F8L4S64/NksTBmKWaHZE46jvI0PyMDAOzcEy9SbNjZAoDi1
YhtuFCIAvyi5PNgeIys/kDjDtiLC1kn9802Nwcz5ingXZjVIL2n9NkvdtD1UfEIZ
oP/fU44cT+HCrQUcy6u4LdX7eh4sMYYeRWxa8TQYQ3W/Sf2AXFNwvo7xBdGOMTRt
vN5jfKE4tLbZTJ0HqOw81w==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
H676rvBnjx03HQKuoTaTJqHC6AUJ2Glsyn9djThexVUCaK3iWiFt2yzOQOV3rkeB
kiw1I08JgEmMeUJ7J+0NMApamk0EKSvhZXWQk/f4G9sAj/NiDhnKHQV6xGq8oPbZ
r+aE7TKK85FjEC+q6OE3PjRck9hiNQ9+P4VBzxCpsR4=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
Bow3eNprMSUzcKh5ujmcijIhOeKoYwRvVcr8NfVsuWWIyhAwtd3nOv4zhIhRLydt
jefboOPyPj3Ab6MhfttkFQsE11HjUnpJQQG6mjXM+8b4gtCsoe6c6qhttWlY4KB5
JTex7Nq5xq7NdfOXH+6L+Sf6aCNvVjTxmrkBj+OiorYBqZCMqLLip9VfS7MWVjVD
yB2yJG6FMmIzSQ5lDJe+ooazHUYLZpwCAZI9SsJ4qQu4JpjMZ+iZ3x6HF1HAM5k0
GcNFn0gXx54vkPvfhgNynJK/22fd83i2ZNJBzem6vlym3a34iMPM2fSIw0otB0WH
mr+sP/0Psix1ptNCTubrjA==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
Y4mY9fi3Q10b3JqWE3JDhUet5DJLizksP+zQpG9bqv4zbX1R21O3QwlNBYi+c2OK
PcwTP8Uc6u9W+wM7goMo5LIvcFYty9GDepeniP8JfobRX3YRkZawn6uduUKHvq7C
ogFUKcz02IccZUGP5UyrcQ80dNQwiOHCdzBRm0ymF2HiDLIZFMsYnbuRL2JHERn3
FCkMvv3Z3a8FYGOFH9VaLnevtrGl78yV3nS6Plcnerk9TdcO/o62UsgW/K9FnF2j
5gkGZqvzSS1gzBADbY+ltAsuMDpC4Uz5BoxrhkY2n9qCgeM8sIe0MR2vo7Zlvhq6
7OKwzVWj+8lkyFHN1FxP+g==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 1040)
`pragma protect data_block
uGBZE9cdccScidZRgNngxnhl6QXv7hcDWkDXuajGQj/lcFC4RDTwuS4ZL7qG9iJO
Xhe1Ipwz3pdvaYy7bMQzVDJ3RL1784Z8GYu55DASaMMQsuHMqPwTgGoELqJL/m6Q
HT/8BILLb1gQAGjJ+RxeA5aUQFnbYPsHhpD67JQmeO8AbHFQ3DLE+iM02nm+AG7x
w7DGh2LZ0rznsV4qo7HWSkrQpuXplHkLZFm8e9PeKoOrPg7nnlKKZ2XrZP/Clyyy
6VMDq2paMs23y/vKzOjkiZzu1yyDLFapT5W8e9q5D2xCrg/nf1CdKBAlpya9eDcj
KD4hVHzRL+OM8LKHfYcxzeuomH7F8F3f4UJjbq/yWA46VA2ec0yKeiQWrbSe8GoJ
J/qdo1El7snUx9n/x1bT6geEwzazN01MS7xORljQBwdUL8qEXulXINaf7CyrayVx
MW8znNI7rUt8NqHYFrT7GiHAczxSDBGfYqhi0h0geCeflzOkYQOt0qwgUCkrMpD7
BB1C0Z3AzF6rjTK9UT8OyTzL5+EVeFE8e44YaB45BVggqdFs/IDo2bCy/RIXER9z
bc4by0xE2GzgfHqZr3zzlBp63/5WohtPz0NPFmfxNpKpGlLYt/+g6nxYPMUPaHwv
i25dm3CT0A93vWbUcre/O6K18StsnbQqHTl8BwtO/idFNiKQG1pGOgEnLQx0k59o
jXH+UqYmM2Zs2LnEJZX40e9benB/+83RU0RR3q8qw4q7LzAolVRXazvL9cWdQ+Ix
SIMpx9o/Dt+IYtckG3y7cALranbd5yG63e8nOZqZuSfdBdRWDEkSr0PpmuDJjrdV
odXPRyHQehLnIuW61RNR5uV+AlGFZ9fBKraQfxqtYLNiXXDFo+RbByeKdErLjKsd
rhTWOXEpF78J+oWTmS0W7mrvZjlURBUQDe/bq6PwNlxRXUw/tujyGhSG3WP8IjeP
XGj1G4GwPjrEm8HW0/ImffNOO+LHkLD3EYJYxzGJdcp34/mcFlqrtq95OQcPQYWG
WEwy6yECyZVEZJvUC8Dm4eE4ZIirVCxDgZn9B8Y8F0FR0LZzmc87E+8M41CAGUar
OaSo+1ndH2tNtRu0L804jcNHi60sDoMl0d/JuOpmyiHUzWns4i0OJ1DTlB++E8/D
DGazEGcVPBUNM39Ue8tiXOLc51RWXDa64THgqQ8gzCWk+pj0l1UfYOERPmugud5t
TqnowzRsvGiAYBS0+gV4W9vr5kvwuefDPDKFwrLkWad+Q32P+skilV8nPxs1lO7q
bO1q9douz7brs/50P7owUoNCJProWeELipFAePk0TGMndG2q5mU8AlByseBlDyO9
A30VJ65NSnaVhJqDnaFvtpItxNA/uU25YRXDELA/HQI=
`pragma protect end_protected

specify
  (clkin => clkout) = (0:0:0, 0:0:0);
endspecify
endmodule
