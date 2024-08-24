# エアコン制御プログラム

## これは何?

ECHONET Liteに対応したエアコンを制御するCGIです。
Free Pascal言語で書かれています。

趣味で書いた開発者向けプログラムです。
デザインも使い方も何もかもが開発者向けです。
一般の方はメーカー製のスマートフォンアプリを使用されるとよいでしょう。

## 対応機種

ECHONET Liteに対応した機種で動いてほしいところですが、規格を網羅するのは大変なので、とりあえずパナソニック エオリア CS-J283DとCS-283DJ用に作っています。
設定については、エアコンの無線機能を有効にし、さらに、接続する無線LANのDHCPサーバーの設定により、エアコンに固定IPアドレスを割り当てています。
メーカー製のスマートフォンアプリは一度も使用していません。

## 対応環境

本CGIはGNU/Linuxで使用することを想定して実装してあります。
CGIが動くHTTPサーバーが必要です。

## 機能

ECHONET Lite規格にある、マルチキャストでネットワーク上の機器を列挙する機能は実装されていません。
そのためDHCPサーバーを設定してエアコンに固定IPアドレスを割り当てる必要があります。

以下の項目をエアコンから取得して表示します:

- 電源
- 節電動作
- 運転モード
- 温度設定
- 室内相対湿度
- 室内温度
- 外気温度
- 風量
- 風向

以下の項目を設定できます:

- 電源 (ON/OFF)
- 節電動作 (通常/節電)
- 運転モード (自動/冷房/暖房/除湿/送風/その他)
- 温度設定 (0-50 ℃)
- 風量 (自動/1/2/3/4/5/6/7/8)
- 風向 (自動/上/上中/中/下中/下)

パナソニック エオリア CS-J283DとCS-283DJでは、以下の制約があります:

- 室内相対湿度は対応プロパティとして列挙されるものの、取得できたことがありません。状態には-が表示されます。
- 外気温度は運転中しか取得できないようです。取得できない時は状態には-が表示されます。
- 温度設定は送風運転の場合は取得できないようです。取得できない時は状態には-が表示され、数値入力欄には25が入ります。
- 節電動作は、温度設定の範囲を変える機能のようです。
- 運転モードのその他は設定できません。
- 温度設定がエアコン側の制約の範囲外の場合は、エラーにはならず、範囲内の値に変更されるようです。例えば0度としても16度になる、というようなことが起きます。
- 風量は7と8は6に、5は4に設定されるようです。リモコンの目盛りごとの風量は2, 3, 4, 6になるようです。

## ビルド

Free Pascalのプログラムなのでビルドの必要があります。
以下のコマンドでビルドできます。

```
fpc aircon.cgi.pas
```

## 設置

CGIが動くHTTPサーバーをエアコンにアクセスできるネットワークにつなぎ適切にファイルを配置します。
また、DHCPサーバーを適切に設定した上でエアコンの無線LANを有効にします。

本CGIは、ファイル名の後ろに`/`をつけて、続けてエアコンのIPアドレスを指定して使用します。
例えば、CGIが`http://192.168.1.1/aircon.cgi`にあり、エアコンが`192.168.1.2`であれば、`http://192.168.1.1/aircon.cgi/192.168.1.2`とします。

IPアドレスに続けてさらに`/`をつけて、エアコン名称を指定することもできます。
指定されたエアコン名称はそのまま出力されます。
複数のエアコンがある場合にわかりやすくする目的で使用できます。
例えば、`http://192.168.1.1/aircon.cgi/192.168.1.2/リビングのエアコン`のようにします。

## 使い方

設置のところで説明したURLにアクセスするとエアコンの状態が表示されます。
変更可能な各項目のラジオボタンが、デフォルトで \[変更しない] になっています。
変更したい項目を選び送信すると変更することができます。
温度設定については、ラジオボタン \[変更する] を選択した上で数字を入れます。

送信すると別画面に切り替わり、送信内容が表示されます。
送信がうまくいくとエアコンのブザー (ビープ音) が鳴ります。
送信後は \[戻る] ボタンで状態の画面に戻ります。

送信内容はGETリクエストになっており、URLにデータがくっついています。
よく使う内容は、そのデータごとブックマークに入れてしまうとよいでしょう。
やったことはないんですが。

インターネットからアクセス可能にする場合はアクセス制御にご注意ください。

受信タイムアウトは5秒にしてあります。
UDPですので何かの拍子にパケットが失われるとタイムアウトします。
タイムアウトになった場合、ネットワークに問題がなければ、webブラウザーの再読み込みで復活できると思います。

## その他

すべての値を常に送るのではなく、\[変更しない] ラジオボタンをもうけたのは、パナソニック エオリア CS-J283DとCS-283DJにおいては付属の赤外線リモコンのほうが多機能であるためです。
0.5度単位の温度設定はそもそもECHONET Liteでは扱えませんし、風向の左右設定やタイマーについてはECHONET Liteの規格にはあってもエアコン側が対応していません。
風量1については逆にリモコンでは選べないかも知れませんが。

ブザーは別に鳴らす必要はないんですが、わかりやすいので何となく入れてみました。
設定をすべて変更しない場合でもブザーだけ鳴らすことができます。
単にブザーを鳴らす項目を一緒に送っているだけですが、パナソニックのエアコンでは、電源オフの時には長めの音が鳴るなど、リモコンと同じような反応をします。

パナソニックのエアコンは、説明書にあるように、単に無線機能だけ有効にしていると、長時間稼働させた後に勝手に電源が切れることがあります。
回避方法は不明です。
メーカー製のスマートフォンアプリを使用する必要があるのかも知れません。

作者はプログラミング経験はそれなりにあるものの、Pascalはほとんど初心者です。
いろいろwebで調べながら適当に書いています。
変なところがたくさんあるかと思いますが気にしないでください。

本ソフトウェアは無保証です。
ライセンスについてはLICENSEファイルをお読みください。
