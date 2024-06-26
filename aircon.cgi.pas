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
   tq	= (Q_MODE,
	   Q_OPERATION_STATUS,
	   Q_POWER_SAVING,
	   Q_OPERATION_MODE,
	   Q_SET_TEMP,
	   Q_SET_TEMP_VALUE,
	   Q_AIR_FLOW_RATE,
	   Q_AIR_FLOW_DIR);
   tqv = array[tq] of string;
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
   header		  = '<!DOCTYPE html><head><title>エアコン制御プログラム</title></head><body>';
   footer		  = '</body>';
   echonetlite_port	  = 3610;
   qs_mode		  = 'mode';
   qs_operation_status	  = 'os';
   qs_power_saving	  = 'ps';
   qs_operation_mode	  = 'om';
   qs_set_temp		  = 'tv';
   qs_set_temp_value	  = 'tvv';
   qs_air_flow_rate	  = 'fr';
   qs_air_flow_dir	  = 'fd';
   qvl_operation_status	  = '10';
   qvl_power_saving	  = 'BA';
   qvl_operation_mode	  = 'ABCDE0';
   qvl_air_flow_rate	  = 'A12345678';
   qvl_air_flow_dir_auto  = '0';
   qvl_air_flow_dir_virt  = 'ADCEB';
   qn_operation_status	  = '電源'#0'OFF'#0'ON'#0;
   qn_power_saving	  = '節電動作'#0'通常'#0'節電'#0;
   qn_operation_mode	  = '運転モード'#0'自動'#0'冷房'#0'暖房'#0'除湿'#0'送風'#0'その他'#0;
   qn_set_temp		  = '温度設定'#0;
   qn_air_flow_rate	  = '風量'#0'自動'#0'1'#0'2'#0'3'#0'4'#0'5'#0'6'#0'7'#0'8'#0;
   qn_air_flow_dir	  = '風向'#0'自動'#0'上'#0'上中'#0'中'#0'下中'#0'下'#0;
   edtl_operation_status  = #$31#$30;
   edtl_power_saving	  = #$42#$41;
   edtl_operation_mode	  = #$41#$42#$43#$44#$45#$40;
   edtl_air_flow_rate	  = #$41#$31#$32#$33#$34#$35#$36#$37#$38;
   edtl_air_flow_dir_auto = #$43;
   edtl_air_flow_dir_virt = #$41#$44#$43#$45#$42;

const
   epccode : array[tepc] of uint8
   = ($80, $8F, $B0, $B3, $BA, $BB, $BE, $A0, $A1, $A4);
   epcname : array[tepc] of ansistring
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

procedure write_radio_tr (st, qs, qn, qvl : string; qvc : char);
var
   index : 0..255;
   qni0	 : 0..255;
   qni1	 : 0..255;
   qni2	 : 0..255;
begin
   qni0 := pos (#0, qn);
   index := pos (qvc, qvl);
   if index > 0 then begin
      qni2 := qni0;
      while index > 0 do begin
	 qni1 := succ (qni2);
	 qni2 := pos (#0, qn, qni1);
	 index := pred (index);
      end;
      st := copy (qn, qni1, qni2 - qni1);
   end;
   write_tr (copy (qn, 1, qni0), st, qs);
   qni2 := qni0;
   for index := 1 to length (qvl) do begin
      qni1 := succ (qni2);
      qni2 := pos (#0, qn, qni1);
      write_radio (qs, qvl[index], '');
      write (copy (qn, qni1, qni2 - qni1));
      write_radio_close;
   end;
   write_tr_close;
end;

procedure edt_to_qvc (edt : uint8;
		      edtl : rawbytestring;
		      qvl : string;
		      var qvc : char);
var
   index : 0..255;
begin
   if qvc = #0 then begin
      for index := 1 to length (edtl) do
	 if ord (edtl[index]) = edt then begin
	    qvc := qvl[index];
	    break;
	 end;
   end;
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
   qvc	   : char;
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
      qvc := #0;
      edt_to_qvc (edt[EPC_OPERATION_STATUS], edtl_operation_status,
		  qvl_operation_status, qvc);
      write_radio_tr ('$' + hexstr (edt[EPC_OPERATION_STATUS], 2),
		      qs_operation_status, qn_operation_status,
		      qvl_operation_status, qvc);
   end;
   if EPC_POWER_SAVING in epcset then begin
      qvc := #0;
      edt_to_qvc (edt[EPC_POWER_SAVING], edtl_power_saving,
		  qvl_power_saving, qvc);
      write_radio_tr ('$' + hexstr (edt[EPC_POWER_SAVING], 2),
		      qs_power_saving, qn_power_saving, qvl_power_saving, qvc);
   end;
   if EPC_OPERATION_MODE in epcset then begin
      qvc := #0;
      edt_to_qvc (edt[EPC_OPERATION_MODE], edtl_operation_mode,
		  qvl_operation_mode, qvc);
      write_radio_tr ('$' + hexstr (edt[EPC_OPERATION_MODE], 2),
		      qs_operation_mode, qn_operation_mode,
		      qvl_operation_mode, qvc);
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
      write_tr (epcname[EPC_SET_TEMP_VALUE], st, qs_set_temp);
      write_radio (qs_set_temp, '0', '');
      write ('変更する: <input type="number" name="tvv" value="',
	     vl, '" id="', qs_set_temp_value, '" max="50" min="0" step="1">');
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
      qvc := #0;
      edt_to_qvc (edt[EPC_AIR_FLOW_RATE], edtl_air_flow_rate,
		  qvl_air_flow_rate, qvc);
      write_radio_tr ('$' + hexstr (edt[EPC_AIR_FLOW_RATE], 2),
		      qs_air_flow_rate, qn_air_flow_rate,
		      qvl_air_flow_rate, qvc);
   end;
   if [EPC_AIR_FLOW_DIR_AUTO, EPC_AIR_FLOW_DIR_VERT] <= epcset then begin
      qvc := #0;
      edt_to_qvc (edt[EPC_AIR_FLOW_DIR_AUTO], edtl_air_flow_dir_auto,
		  qvl_air_flow_dir_auto, qvc);
      edt_to_qvc (edt[EPC_AIR_FLOW_DIR_VERT], edtl_air_flow_dir_virt,
		  qvl_air_flow_dir_virt, qvc);
      write_radio_tr ('$' + hexstr (edt[EPC_AIR_FLOW_DIR_AUTO], 2) +
		      ', $' + hexstr (edt[EPC_AIR_FLOW_DIR_VERT], 2),
		      qs_air_flow_dir, qn_air_flow_dir,
		      qvl_air_flow_dir_auto + qvl_air_flow_dir_virt, qvc);
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

function make_prop (epc	: tepc; qv : tqv) : rawbytestring;
var
   edt : char;
begin
   case epc of
     EPC_OPERATION_STATUS  : edt := make_radio_edt (qv[Q_OPERATION_STATUS],
						    qvl_operation_status,
						    edtl_operation_status);
     EPC_POWER_SAVING	   : edt := make_radio_edt (qv[Q_POWER_SAVING],
						    qvl_power_saving,
						    edtl_power_saving);
     EPC_OPERATION_MODE	   : edt := make_radio_edt (qv[Q_OPERATION_MODE],
						    qvl_operation_mode,
						    edtl_operation_mode);
     EPC_SET_TEMP_VALUE	   : edt := make_int_edt (qv[Q_SET_TEMP_VALUE], 0, 50);
     EPC_AIR_FLOW_RATE	   : edt := make_radio_edt (qv[Q_AIR_FLOW_RATE],
						    qvl_air_flow_rate,
						    edtl_air_flow_rate);
     EPC_AIR_FLOW_DIR_AUTO : edt := make_radio_edt (qv[Q_AIR_FLOW_DIR],
						    qvl_air_flow_dir_auto,
						    edtl_air_flow_dir_auto);
     EPC_AIR_FLOW_DIR_VERT : edt := make_radio_edt (qv[Q_AIR_FLOW_DIR],
						    qvl_air_flow_dir_virt,
						    edtl_air_flow_dir_virt);
   end;
   make_prop := chr (epccode[epc]) {EPC} + #$01 {PDC} + edt;
end;

procedure mode_set (sh : longint; sa : tinetsockaddr; qv : tqv);
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
   if qv[Q_OPERATION_STATUS] <> 'keep' then
      epcset := epcset + [EPC_OPERATION_STATUS];
   if qv[Q_POWER_SAVING] <> 'keep' then
      epcset := epcset + [EPC_POWER_SAVING];
   if qv[Q_OPERATION_MODE] <> 'keep' then
      epcset := epcset + [EPC_OPERATION_MODE];
   if qv[Q_SET_TEMP] <> 'keep' then
      epcset := epcset + [EPC_SET_TEMP_VALUE];
   if qv[Q_AIR_FLOW_RATE] <> 'keep' then
      epcset := epcset + [EPC_AIR_FLOW_RATE];
   if qv[Q_AIR_FLOW_DIR] <> 'keep' then begin
      if qv[Q_AIR_FLOW_DIR] = '0' then begin
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

function get_query_string : tqv;
var
   qs : string;
   q  : tq;
   qv : tqv;
   pe : 0..255;
   pa : 0..255;
   nm : string;
   vl : string;
begin
   for q := low (qv) to high (qv) do
      qv[q] := '';
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
	qs_mode		    : q := Q_MODE;
	qs_operation_status : q := Q_OPERATION_STATUS;
	qs_power_saving	    : q := Q_POWER_SAVING;
	qs_operation_mode   : q := Q_OPERATION_MODE;
	qs_set_temp	    : q := Q_SET_TEMP;
	qs_set_temp_value   : q := Q_SET_TEMP_VALUE;
	qs_air_flow_rate    : q := Q_AIR_FLOW_RATE;
	qs_air_flow_dir	    : q := Q_AIR_FLOW_DIR;
      else
	 show_error ('エラー: QUERY_STRINGに不正な名前が指定されました。',
		     false);
      end;
      qv[q] := vl;
   end;
   get_query_string := qv;
end;

procedure show_main (path_info : string);
var
   sa : tinetsockaddr;
   sh : longint;
   qv : tqv;
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
   case qv[Q_MODE] of
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
