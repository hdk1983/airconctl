(*
    エアコン制御プログラム
    Copyright (C) 2024  Hideki EIRAKU <hdk_2@users.sourceforge.net>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

program aircon_cgi;
uses dos,sockets,sysutils;

type
   tqval = record
	      mode, os, ps, om, tv, tvv, fr, fd	: string;
	   end;
   tepc	= (EPC_OPERATION_STATUS,
	   EPC_POWER_SAVING,
	   EPC_OPERATION_MODE,
	   EPC_SET_TEMP_VALUE,
	   EPC_MEASURED_HUMIDITY,
	   EPC_MEASURED_ROOM_TEMP,
	   EPC_MEASURED_OUT_TEMP,
	   EPC_AIR_FLOW_RATE,
	   EPC_AIR_FLOW_DIR_AUTO,
	   EPC_AIR_FLOW_DIR_VERT);

const
   header	    = '<!DOCTYPE html><head><title>エアコン制御プログラム</title></head><body>';
   footer	    = '</body>';
   echonetlite_port = 3610;

const
   epccode : array[EPC_OPERATION_STATUS..EPC_AIR_FLOW_DIR_VERT] of uint8
   = ($80, $8F, $B0, $B3, $BA, $BB, $BE, $A0, $A1, $A4);
   epcname : array[EPC_OPERATION_STATUS..EPC_AIR_FLOW_DIR_VERT] of string
   = ('電源', '節電動作', '運転モード', '温度設定', '室内相対湿度', '室内温度',
      '外気温度', '風量', '風向自動', '風向上下');

procedure show_error (error : string; usage : boolean);
begin
   if usage then begin
      writeln (header, error,
	       '<p>URLに/とIPアドレスをつけてアクセスしてください。</p>',
	       '<p>付加する文字列の例: /192.168.1.2</p>',
	       footer);
   end else begin
      writeln (header, error, footer);
   end;
   halt;
end;

procedure show_list;
begin
   show_error ('', true);
end;

procedure write_radio (fname, value, arg : string);
begin
   write ('<input type="radio" name="', fname, '"',
	  ' value="', value, '" id="', fname, '_', value, '"', arg, '>',
	  '<label for="', fname, '_', value, '">');
end;

procedure write_radio_close;
begin
   write ('</label>');
end;

procedure write_tr (name, st, fname : string);
begin
   write ('<tr><td>', name, '</td><td>', st, '</td><td>');
   if length (fname) > 0 then begin
      write_radio (fname, 'keep', ' checked');
      write ('変更しない');
      write_radio_close;
   end;
end;

procedure write_tr_close;
begin
   writeln ('</td></tr>');
end;

procedure show_status (sh : longint; sa : tinetsockaddr);
const
   sndbuf : array[1..32] of uint8 = ($10, {EHD1}
				     $81, {EHD2}
				     $00, {TID}
				     $01, {TID}
				     $05, {SEOJ X1}
				     $FF, {SEOJ X2}
				     $01, {SEOJ X3}
				     $01, {DEOJ X1}
				     $30, {DEOJ X2}
				     $01, {DEOJ X3}
				     $62, {ESV}
				     $0A, {OPC}
				     $80, {EPC 1: 動作状態}
				     $00, {PDC 1}
				     $8F, {EPC 2: 節電動作設定}
				     $00, {PDC 2}
				     $B0, {EPC 3: 運転モード設定}
				     $00, {PDC 3}
				     $B3, {EPC 4: 温度設定値}
				     $00, {PDC 4}
				     $BA, {EPC 5: 室内相対湿度 計測値}
				     $00, {PDC 5}
				     $BB, {EPC 6: 室内温度計測値}
				     $00, {PDC 6}
				     $BE, {EPC 7: 外気温度計測値}
				     $00, {PDC 7}
				     $A0, {EPC 8: 風量設定}
				     $00, {PDC 8}
				     $A1, {EPC 9: 風向自動設定}
				     $00, {PDC 9}
				     $A4, {EPC 10: 風向上下設定}
				     $00); {PDC 10}
   rcvexp : array[1..10] of uint8 = ($10,  {EHD1}
				     $81,  {EHD2}
				     $00,  {TID}
				     $01,  {TID}
				     $01,  {SEOJ X1}
				     $30,  {SEOJ X2}
				     $01,  {SEOJ X3}
				     $05,  {DEOJ X1}
				     $FF,  {DEOJ X2}
				     $01); {DEOJ X3}
var
   rcvbuf  : array[1..64] of uint8;
   rcvlen  : longint;
   i	   : 1..64;
   offset  : 1..64;
   epctype : tepc;
   edt	   : array[tepc] of uint8;
   epcset  : set of tepc;
   st	   : string;
   vl	   : uint8;

begin
   if fpsendto (sh, @sndbuf, sizeof (sndbuf), 0, @sa, sizeof (sa)) = -1 then
      show_error ('エラー: 送信できませんでした。', false);
   rcvlen := fprecv (sh, @rcvbuf, sizeof (rcvbuf), 0);
   if rcvlen = -1 then
      show_error ('エラー: 受信できませんでした。', false);
   if comparebyte (rcvbuf, rcvexp, sizeof (rcvexp)) <> 0 then
      show_error ('エラー: 不正な応答を受信しました。', false);
   if rcvbuf[11] <> $72 then begin	   {ESV}
      if rcvbuf[11] = $52 then
	 show_error ('エラー: プロパティ値読み出し不可応答を受信しました。',
		     false);
      show_error ('エラー: 不正なESV $' + hexstr (rcvbuf[11], 2) +
		  ' を受信しました。', false);
   end;
   offset := 13;
   epcset := [];
   for i := 1 to rcvbuf[12] do begin	   {OPC}
      if rcvbuf[offset + 1] > 0 then begin
	 if rcvbuf[offset + 1] <> 1 then
	    show_error ('エラー: EPC $' + hexstr (rcvbuf[offset], 2) +
			' について不正な長さ $' +
			hexstr (rcvbuf[offset + 1], 2) +
			' の応答を受信しました。', false);
	 case rcvbuf[offset] of		   {EPC i}
	   $80 : epctype := EPC_OPERATION_STATUS;
	   $8F : epctype := EPC_POWER_SAVING;
	   $B0 : epctype := EPC_OPERATION_MODE;
	   $B3 : epctype := EPC_SET_TEMP_VALUE;
	   $BA : epctype := EPC_MEASURED_HUMIDITY;
	   $BB : epctype := EPC_MEASURED_ROOM_TEMP;
	   $BE : epctype := EPC_MEASURED_OUT_TEMP;
	   $A0 : epctype := EPC_AIR_FLOW_RATE;
	   $A1 : epctype := EPC_AIR_FLOW_DIR_AUTO;
	   $A4 : epctype := EPC_AIR_FLOW_DIR_VERT;
	 else
	    show_error ('エラー: 不正な EPC $' + hexstr (rcvbuf[offset], 2) +
			' の応答を受信しました。', false);
	 end;
	 edt[epctype] := rcvbuf[offset + 2];
	 epcset := epcset + [epctype];
      end;
      offset := offset + 2 + rcvbuf[offset + 1];
      if offset >= rcvlen then
	 break;
   end;

   writeln (header,
	    '<form method="GET">',
	    '<input type="hidden" name="mode" value="set">',
	    '<p><input type="reset"></p>',
	    '<table>',
	    '<tr><th>項目</th><th>状態</th><th>変更</th></tr>');
   if EPC_OPERATION_STATUS in epcset then begin
      st := '$' + hexstr (edt[EPC_OPERATION_STATUS], 2);
      case edt[EPC_OPERATION_STATUS] of
	$30 : st := 'ON';
	$31 : st := 'OFF';
      end;
      write_tr (epcname[EPC_OPERATION_STATUS], st, 'os');
      write_radio ('os', '1', ''); write ('OFF'); write_radio_close;
      write_radio ('os', '0', ''); write ('ON'); write_radio_close;
      write_tr_close;
   end;
   if EPC_POWER_SAVING in epcset then begin
      st := '$' + hexstr (edt[EPC_POWER_SAVING], 2);
      case edt[EPC_POWER_SAVING] of
	$41 : st := '節電';
	$42 : st := '通常';
      end;
      write_tr (epcname[EPC_POWER_SAVING], st, 'ps');
      write_radio ('ps', 'B', ''); write ('通常'); write_radio_close;
      write_radio ('ps', 'A', ''); write ('節電'); write_radio_close;
      write_tr_close;
   end;
   if EPC_OPERATION_MODE in epcset then begin
      st := '$' + hexstr (edt[EPC_OPERATION_MODE], 2);
      case edt[EPC_OPERATION_MODE] of
	$41 : st := '自動';
	$42 : st := '冷房';
	$43 : st := '暖房';
	$44 : st := '除湿';
	$45 : st := '送風';
	$40 : st := 'その他';
      end;
      write_tr (epcname[EPC_OPERATION_MODE], st, 'om');
      write_radio ('om', 'A', ''); write ('自動'); write_radio_close;
      write_radio ('om', 'B', ''); write ('冷房'); write_radio_close;
      write_radio ('om', 'C', ''); write ('暖房'); write_radio_close;
      write_radio ('om', 'D', ''); write ('除湿'); write_radio_close;
      write_radio ('om', 'E', ''); write ('送風'); write_radio_close;
      write_radio ('om', '0', ''); write ('その他'); write_radio_close;
      write_tr_close;
   end;
   if EPC_SET_TEMP_VALUE in epcset then begin
      st := '$' + hexstr (edt[EPC_SET_TEMP_VALUE], 2);
      vl := 25;
      if edt[EPC_SET_TEMP_VALUE] = $FD then begin
	 st := '-';
      end else if edt[EPC_SET_TEMP_VALUE] <= 50 then begin
	 str (edt[EPC_SET_TEMP_VALUE], st);
	 st := st + '℃';
	 vl := edt[EPC_SET_TEMP_VALUE];
      end;
      write_tr (epcname[EPC_SET_TEMP_VALUE], st, 'tv');
      write_radio ('tv', '0', '');
      write ('変更する: <input type="number" name="tvv" value="',
	     vl, '" id="tvv" max="50" min="0" step="1">');
      write_radio_close;
      write_tr_close;
   end;
   if EPC_MEASURED_HUMIDITY in epcset then begin
      st := '$' + hexstr (edt[EPC_MEASURED_HUMIDITY], 2);
      if edt[EPC_MEASURED_HUMIDITY] = $FD then begin
	 st := '-';
      end else if edt[EPC_MEASURED_HUMIDITY] <= 100 then begin
	 str (edt[EPC_MEASURED_HUMIDITY], st);
	 st := st + '%';
      end;
      write_tr (epcname[EPC_MEASURED_HUMIDITY], st, '');
      write_tr_close;
   end;
   if EPC_MEASURED_ROOM_TEMP in epcset then begin
      st := '$' + hexstr (edt[EPC_MEASURED_ROOM_TEMP], 2);
      if edt[EPC_MEASURED_ROOM_TEMP] = $7E then begin
	 st := '-';
      end else if edt[EPC_MEASURED_ROOM_TEMP] = $7F then begin
	 st := '高すぎる';
      end else if edt[EPC_MEASURED_ROOM_TEMP] = $80 then begin
	 st := '低すぎる';
      end else begin
	 str (int8 (edt[EPC_MEASURED_ROOM_TEMP]), st);
	 st := st + '℃';
      end;
      write_tr (epcname[EPC_MEASURED_ROOM_TEMP], st, '');
      write_tr_close;
   end;
   if EPC_MEASURED_OUT_TEMP in epcset then begin
      st := '$' + hexstr (edt[EPC_MEASURED_OUT_TEMP], 2);
      if edt[EPC_MEASURED_OUT_TEMP] = $7E then begin
	 st := '-';
      end else if edt[EPC_MEASURED_OUT_TEMP] = $7F then begin
	 st := '高すぎる';
      end else if edt[EPC_MEASURED_OUT_TEMP] = $80 then begin
	 st := '低すぎる';
      end else begin
	 str (int8 (edt[EPC_MEASURED_OUT_TEMP]), st);
	 st := st + '℃';
      end;
      write_tr (epcname[EPC_MEASURED_OUT_TEMP], st, '');
      write_tr_close;
   end;
   if EPC_AIR_FLOW_RATE in epcset then begin
      st := '$' + hexstr (edt[EPC_AIR_FLOW_RATE], 2);
      case edt[EPC_AIR_FLOW_RATE] of
	$41 : st := '自動';
	$31 : st := '1/8';
	$32 : st := '2/8';
	$33 : st := '3/8';
	$34 : st := '4/8';
	$35 : st := '5/8';
	$36 : st := '6/8';
	$37 : st := '7/8';
	$38 : st := '8/8';
      end;
      write_tr (epcname[EPC_AIR_FLOW_RATE], st, 'fr');
      write_radio ('fr', 'A', ''); write ('自動'); write_radio_close;
      write_radio ('fr', '1', ''); write ('1'); write_radio_close;
      write_radio ('fr', '2', ''); write ('2'); write_radio_close;
      write_radio ('fr', '3', ''); write ('3'); write_radio_close;
      write_radio ('fr', '4', ''); write ('4'); write_radio_close;
      write_radio ('fr', '5', ''); write ('5'); write_radio_close;
      write_radio ('fr', '6', ''); write ('6'); write_radio_close;
      write_radio ('fr', '7', ''); write ('7'); write_radio_close;
      write_radio ('fr', '8', ''); write ('8'); write_radio_close;
      write_tr_close;
   end;
   if (EPC_AIR_FLOW_DIR_AUTO in epcset) and (EPC_AIR_FLOW_DIR_VERT in epcset) then begin
      st := '$' + hexstr (edt[EPC_AIR_FLOW_DIR_AUTO], 2) + ', $' + hexstr (edt[EPC_AIR_FLOW_DIR_VERT], 2);
      if edt[EPC_AIR_FLOW_DIR_AUTO] = $43 then begin
	 st := '自動';
      end else if edt[EPC_AIR_FLOW_DIR_AUTO] = $42 then begin
	 case edt[EPC_AIR_FLOW_DIR_VERT] of
	   $41 : st := '上';
	   $42 : st := '下';
	   $43 : st := '中';
	   $44 : st := '上中';
	   $45 : st := '下中';
	 end;
      end;
      write_tr ('風向', st, 'fd');
      write_radio ('fd', '0', ''); write ('自動'); write_radio_close;
      write_radio ('fd', 'A', ''); write ('上'); write_radio_close;
      write_radio ('fd', 'D', ''); write ('上中'); write_radio_close;
      write_radio ('fd', 'C', ''); write ('中'); write_radio_close;
      write_radio ('fd', 'E', ''); write ('下中'); write_radio_close;
      write_radio ('fd', 'B', ''); write ('下'); write_radio_close;
      write_tr_close;
   end;
   writeln ('</table>',
	    '<p><input type="submit"></p>',
	    '</form>', footer);
end;

function make_radio_edt (value, options	: string; edts : rawbytestring) : char;
var
   index : 0..255;
begin
   index := 0;
   if length (value) = 1 then
      index := pos (value, options);
   if index = 0 then
      show_error ('エラー: フォームから渡された値が不正です。', false);
   make_radio_edt := edts[index];
end;

function make_int_edt (value : string; minval, maxval : uint8) : char;
var
   i, code : integer;
begin
   val (value, i, code);
   if code <> 0 then
      show_error ('エラー: 不正な整数値です。', false);
   if i < minval then
      show_error ('エラー: 整数値が小さすぎます。', false);
   if i > maxval then
      show_error ('エラー: 整数値が大きすぎます。', false);
   make_int_edt := chr (i);
end;

function make_prop (epc	: tepc; qv : tqval) : rawbytestring;
var
   edt : char;
begin
   case epc of
     EPC_OPERATION_STATUS  : edt := make_radio_edt (qv.os, '10', #$31#$30);
     EPC_POWER_SAVING	   : edt := make_radio_edt (qv.ps, 'BA', #$42#$41);
     EPC_OPERATION_MODE	   : edt := make_radio_edt (qv.om, 'ABCDE0',
						    #$41#$42#$43#$44#$45#$40);
     EPC_SET_TEMP_VALUE	   : edt := make_int_edt (qv.tvv, 0, 50);
     EPC_AIR_FLOW_RATE	   : edt := make_radio_edt (qv.fr, 'A12345678',
						    #$41#$31#$32#$33#$34 +
						    #$35#$36#$37#$38);
     EPC_AIR_FLOW_DIR_AUTO : edt := make_radio_edt (qv.fd, '0', #$43);
     EPC_AIR_FLOW_DIR_VERT : edt := make_radio_edt (qv.fd, 'ABCDE',
						    #$41#$42#$43#$44#$45);
   end;
   make_prop := chr (epccode[epc]) {EPC} + #$01 {PDC} + edt;
end;

procedure mode_set (sh : longint; sa : tinetsockaddr; qv : tqval);
var
   epcset  : set of tepc;
   epc	   : tepc;
   count   : byte;
   sndbuf  : rawbytestring;
   rcvbuf  : rawbytestring;
   rcvlen  : longint;
   i	   : 0..255;
   success : boolean;
begin
   epcset := [];
   if qv.os <> 'keep' then epcset := epcset + [EPC_OPERATION_STATUS];
   if qv.ps <> 'keep' then epcset := epcset + [EPC_POWER_SAVING];
   if qv.om <> 'keep' then epcset := epcset + [EPC_OPERATION_MODE];
   if qv.tv <> 'keep' then epcset := epcset + [EPC_SET_TEMP_VALUE];
   if qv.fr <> 'keep' then epcset := epcset + [EPC_AIR_FLOW_RATE];
   if qv.fd <> 'keep' then begin
      if qv.fd = '0' then begin
	 epcset := epcset + [EPC_AIR_FLOW_DIR_AUTO];
      end else begin
	 epcset := epcset + [EPC_AIR_FLOW_DIR_VERT];
      end;
   end;
   count := 0;
   for epc in epcset do
      count := count + 1;
   sndbuf := (#$10#$81 {EHD} + #$00#$01 {TID} +
	      #$05#$FF#$01 {SEOJ} + #$01#$30#$01 {DEOJ} +
	      #$61 {ESV} + chr (count + 1) {OPC});
   for epc in epcset do
      sndbuf := sndbuf + make_prop (epc, qv);
   sndbuf := sndbuf + #$D0#$01#$41;	   {ブザー}
   if fpsendto (sh, @sndbuf[1], length (sndbuf), 0, @sa,
		sizeof (sa)) = -1 then
      show_error ('エラー: 送信できませんでした。', false);
   setlength (rcvbuf, 255);
   rcvlen := fprecv (sh, @rcvbuf[1], length (rcvbuf), 0);
   if rcvlen = -1 then
      show_error ('エラー: 受信できませんでした。', false);
   setlength (rcvbuf, rcvlen);
   writeln (header);
   success := true;
   write ('<p>設定項目名:');
   for epc in epcset do
      write (' ', epcname[epc]);
   writeln ('</p>');
   write ('<p>送信データ:');
   for i := 1 to length (sndbuf) do
      writeln (hexstr (ord (sndbuf[i]), 2));
   writeln ('</p>');
   write ('<p>受信データ:');
   for i := 1 to length (rcvbuf) do
      writeln (hexstr (ord (rcvbuf[i]), 2));
   writeln ('</p>');
   if (copy (sndbuf, 1, 4) <> copy (rcvbuf, 1, 4)) or {EHD and TID}
      (copy (sndbuf, 5, 3) <> copy (rcvbuf, 8, 3)) or {SEOJ and DEOJ}
      (copy (sndbuf, 8, 3) <> copy (rcvbuf, 5, 3)) then {DEOJ and SEOJ}
   begin
      success := false;
      writeln ('<p>エラー: 不正な応答を受信しました。</p>');
   end;
   if rcvbuf[11] <> #$71 then begin			   {ESV}
      success := false;
      if rcvbuf[11] = #$51 then begin
	 writeln ('<p>エラー: プロパティ値書き込み要求不可応答を' +
		  '受信しました。</p>');
      end else begin
	 writeln ('<p>エラー: 不正なESV $', hexstr (ord (rcvbuf[11]), 2),
		  ' を受信しました。');
      end;
   end;
   if success then
      writeln ('<p>成功しました。</p>');
   writeln ('<form><input type="submit" value="戻る"></form>');
   writeln (footer);
end;

function get_addr_from_path_info (path_info : string) : in_addr;
var
   name	: string;
   ret	: in_addr;
begin
   name := copy (path_info, 2);
   ret := StrToHostAddr (name);
   if ret.s_addr = 0 then
      show_error ('エラー: IPアドレスが正しくありません。', true);
   ret.s_addr := htonl (ret.s_addr);
   get_addr_from_path_info := ret;
end;

function get_query_string : tqval;
var
   qs : string;
   qv : tqval;
   pe : 0..255;
   pa : 0..255;
   nm : string;
   vl : string;
begin
   with qv do begin
      mode := '';
      os := '';
      ps := '';
      om := '';
      tv := '';
      tvv := '';
      fr := '';
      fd := '';
   end;
   qs := getenv ('QUERY_STRING');
   {name1=value1&name2=value2形式の文字列を分解する。
   コピーだらけで遅いけど確実に。}
   while length (qs) > 0 do begin
      pe := pos ('=', qs);
      pa := pos ('&', qs);
      if (pe <= 1) or ((pa > 0) and (pa <= pe)) then
	 show_error ('エラー: 不正なQUERY_STRINGです。', false);
      nm := copy (qs, 1, pe - 1);
      if pa > 0 then begin
	 vl := copy (qs, pe + 1, pa - pe - 1);
	 qs := copy (qs, pa + 1);
      end else begin
	 vl := copy (qs, pe + 1);
	 qs := '';
      end;
      case nm of
	'mode' : qv.mode := vl;
	'os'   : qv.os := vl;
	'ps'   : qv.ps := vl;
	'om'   : qv.om := vl;
	'tv'   : qv.tv := vl;
	'tvv'  : qv.tvv := vl;
	'fr'   : qv.fr := vl;
	'fd'   : qv.fd := vl;
      else
	 show_error ('エラー: QUERY_STRINGに不正な名前が指定されました。',
		     false);
      end;
   end;
   get_query_string := qv;
end;

procedure show_main (path_info : string);
var
   sa : tinetsockaddr;
   sh : longint;
   qv : tqval;
begin
   if (path_info[1] <> '/') then
      show_error ('エラー: PATH_INFOが/で始まっていません。', true);

   {ソケットを準備する}
   sh := fpsocket (AF_INET, SOCK_DGRAM, 0);
   if sh = -1 then
      show_error ('エラー: ソケットを作成できませんでした。', false);
   fillchar (sa, sizeof (sa), 0);
   sa.sin_family := AF_INET;
   sa.sin_port := htons (echonetlite_port);
   sa.sin_addr := noaddress;
   if fpbind (sh, @sa, sizeof (sa)) = -1 then
      show_error ('エラー: 送信元をバインドできませんでした。', false);
   fillchar (sa, sizeof (sa), 0);
   sa.sin_family := AF_INET;
   sa.sin_port := htons (echonetlite_port);
   sa.sin_addr := get_addr_from_path_info (path_info);

   qv := get_query_string;
   case qv.mode of
     ''	   : show_status (sh, sa);
     'set' : mode_set (sh, sa, qv);
   else
      show_error ('エラー: 不正なmodeが指定されました。', false);
   end;
end;

var
   path_info : string;

begin
   writeln ('Content-type: text/html; charset=utf-8');
   writeln ('');
   path_info := getenv ('PATH_INFO');
   if (length (path_info) = 0) then begin
      show_list;
   end else begin
      show_main (path_info);
   end;
end.
