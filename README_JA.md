# Pokémon Champions Android 60FPS Runtime Research

[English](README.md) | 日本語

Pokémon Champions Android版を、Google Playから入手した正規版のゲーム本体を
改変せず、ランタイムフックによって60 FPS化する非公式の研究プロジェクトです。
検証済みの環境とバージョンに限定した結果を扱っており、すべての端末での動作を
保証するものではありません。

## 概要

このプロジェクトは、正規のGoogle Play版をそのまま使い、ゲーム起動後の
runtimeでフレームペーシングだけを調整します。APKの再パッケージ化、patch、
re-sign、ゲームの再配布は行いません。ユーザー向けの推奨配布物は、maintainerが
ビルドしたReZygisk互換module ZIPです。ソースからのbuild手順は、研究、検証、
contributor向けに用意されています。

対象はフレームレート関連のruntime入力だけです。ゲームプレイの内容、ネットワーク
通信、セーブデータ、ポケモンデータを変更するものではありません。

## プロジェクトの状態

現行のproduction baselineは、CODE-01 runtime auditと、検証済みBlueStacks環境での
Frida-free automatic bootstrap gateにPASSしています。別の物理Windowsホスト上に
構築した隔離fresh-install環境でも、同じbaselineの検証にPASSしました。
[Fresh-install validation](docs/FRESH_INSTALL_VALIDATION.md)に記録があります。

検証時のrecordingでは、実際に描画された固有フレームが約60 FPSとなり、
trainer/human animationも滑らかになりました。これは記載した環境での研究結果であり、
端末全般の互換性を示すものではありません。

検証済みのv0.2.0-poc releaseとmodule ZIPは、
[GitHub Release](https://github.com/piuteu/Pokemon-Champions-60FPS-Android/releases/tag/v0.2.0-poc)
から確認できます。

## 機能

- Unityの`Application.set_targetFrameRate`をruntime-onlyでフック
- `30`と`-1`の要求を、元のsetterを呼び出しながら実効`60`へ変更
- 実証済みの`AnimationPlayer.AdvanceTime`経路に限定して
  `AnimationClip.frameRate`をフック。元の`30.0f`を`60.0f`へ変更しつつ、
  元のtime、duration、event、playback logicを維持
- Fridaを使わない自動ReZygisk bootstrap
- x86_64 bootstrap → NativeBridge/Houdini → ARM64 guest payload
- 通常のlauncher起動、force-stop/relaunch、full BlueStacks restart後も状態を維持
- moduleをdisableするとstock動作へ戻る。uninstall手順は文書化されていますが、
  独立した検証は未実施
- residual 30 Hz auditとtransient frame-drop profilingをresearch documentation
  として保持

## 対応バージョン

| ゲーム | versionCode | 状態 |
| --- | ---: | --- |
| Pokémon Champions Android 1.1.5 | 3191 | Supported / validated |
| Future versions | — | 未検証。可能な範囲でfail open |

一覧にないversionは、Unity/IL2CPP layout、関連するhash/signature、offset、
runtime hook、animation動作、60 FPS結果が検証されるまでstock状態を維持します。

## 仕組み

```text
Pokémon Champions normal launch
        ↓
x86_64 ReZygisk bootstrap
        ↓
package + version guard
        ↓
payload staging and integrity verification
        ↓
application ClassLoader
        ↓
Runtime.load0
        ↓
NativeBridge / Houdini
        ↓
ARM64 payload
        ↓
Unity runtime hooks
        ↓
60 FPS + targeted animation timing correction
```

payloadは元のUnity functionを保持し、検証済みのframe-rate inputだけを変更します。
ゲームの`MOV W0,#30` instructionをpatchせず、無関係な初期化を抑制せず、
`Surface.setFrameRate`をゲームrenderingの代用として呼び出すこともありません。

## なぜruntime-onlyなのか

改変APKや抽出したgame libraryは、通常のインストール、licensing、asset、
update動作を壊す可能性があります。このプロジェクトでは、Google Play app、
split、manifest、proprietary native libraryを変更せず、ゲームが通常起動した後に
runtime hookだけを読み込みます。

## 必要な環境

このプロジェクトで検証済みなのは、次の構成だけです。

- Pokémon Champions Android 1.1.5 / 3191の正規Google Playインストール
- BlueStacks Tiramisu64、Android 13 / API 33、x86_64、
  ARM64 NativeBridge/Houdini
- root化済みでReZygiskに対応した環境
- 対応するmodule managerからインストールするmaintainer提供のmodule ZIP

通常利用にFridaは必要ありません。その他の物理端末、emulator、root manager、
その他の設定は未検証です。

## インストール

1. Pokémon Championsの正規Google Play版を自分でインストール、または利用します。
2. 検証済みのroot化済みBlueStacks/ReZygisk環境を準備します。
3. 対応するmanagerからmaintainer提供のmodule ZIPをインストールします。
   payloadをapp内へ手動コピーしないでください。
4. managerの指示に従って再起動します。
5. Pokémon Championsを通常のlauncherから起動します。
6. 期待される60 FPS動作とtrainer/human animationの結果を確認します。

このrepositoryはAPK、split APK、game asset、metadata、`libil2cpp.so`、
`libunity.so`を配布しません。

## 無効化 / アンインストール

`PCFPS Zygisk Auto Bootstrap`が対応するmanagerのUIに表示される場合は、通常どおり
managerからdisableして再起動してください。ゲームはstock動作で起動します。
managerのUIにmoduleが表示されない場合は、次のmodule-state fallbackを使います。

```sh
adb shell su -c "touch /data/adb/modules/pcfps_zygisk_auto_bootstrap/disable"
```

その後、BlueStacksを再起動します。再有効化する場合はmarkerを削除して、もう一度
再起動してください。

```sh
adb shell su -c "rm /data/adb/modules/pcfps_zygisk_auto_bootstrap/disable"
```

これらの手順はmodule stateだけを変更します。payloadを手動コピーしたり、
game fileを変更したりしないでください。uninstall手順は対応するmanagerに
記載されていますが、validation runでは独立検証していません。ゲームの
再インストールは通常のrevert手順ではありません。

## ソースからのbuild

このプロジェクトはdirect NDK clang compilationを使用します。Android Studio、
Gradle、CMake、Ninja、APK tooling、signing tool、application repackagingは
必要ありません。NDK rootを明示するか、現在のPowerShell processで
`ANDROID_NDK_HOME`または`ANDROID_NDK_ROOT`を設定してください。

```powershell
& .\scripts\build.ps1 -NdkRoot <android-ndk>
& .\scripts\build-zygisk-bootstrap.ps1 -NdkRoot <android-ndk>
& .\scripts\package-zygisk-module.ps1
```

scriptは検証済みのNDK r27d family、Android API 33 target、ARM64 payload、
x86_64 bootstrapを維持します。`-UnblockNdk`はWindows troubleshooting用の
optional switchです。標準ではrecursiveに実行されません。

```powershell
& .\scripts\build.ps1 -NdkRoot <android-ndk> -UnblockNdk
```

ignore対象のoutputは`build/`以下に書き出されます。

## 検証

canonical module ZIPの内容は次の3ファイルだけです。

```text
module.prop
zygisk/x86_64.so
payload/libpcfps_runtime.so
```

clean payloadはELF64 AArch64、bootstrapはELF64 x86_64です。build logには
ARM64 constructor、`JNI_OnLoad`、hook installation成功、`Runtime.load0` returnが
現れる必要があります。検証記録とartifact processは
[CODE-01 audit](docs/CODE_AUDIT.md)と[validation documentation](docs/VALIDATION.md)
にまとめています。

## 既知の制限

- 現在検証済みなのは1.1.5 / 3191だけです。
- 現在の検証環境はBlueStacks Tiramisu64です。
- future versionでは再auditが必要で、stale hookを読み込まずfail openする場合があります。
- BlueStacks profilingではtransient missed-vsync/frame-slot hitchが観測されており、
  non-blockingなresearch limitationとして記録しています。
- 検証時の60 FPS recordingは、すべての端末、scene、display policy、future game
  versionで同じ結果になることを保証しません。universal device compatibilityは
  主張していません。

## 新しいゲームversionへの対応

各updateについて、次を実施します。

1. 新しいgame versionと`versionCode`を検出する。
2. Unity/IL2CPP layoutに変更があるか調べる。
3. 関連するhash、signature、offsetを検証する。
4. 古いhardcoded offsetを根拠なく再利用しない。
5. evidenceが得られるまでversion-specific constantを更新しない。
6. ARM64 payloadとx86_64 bootstrapを再buildする。
7. runtime loadingとfail-open動作を検証する。
8. 60 FPS renderingとanimation動作を検証する。
9. 必要な全checkがPASSしてからversionをsupportedと記載する。

## 研究ドキュメント

- [Architecture](docs/ARCHITECTURE.md)
- [Automatic bootstrap](docs/AUTO_BOOTSTRAP.md)
- [Version 1.1.5 facts](docs/VERSION_1.1.5.md)
- [Validation](docs/VALIDATION.md)
- [Residual 30 Hz audit](docs/RESIDUAL_30HZ_AUDIT.md)
- [Transient drop audit](docs/PERF_TRANSIENT_DROPS.md)
- [Research notes](docs/RESEARCH_NOTES.md)
- [Production cleanup audit](docs/CODE_AUDIT.md)
- [Public release checklist](docs/PUBLIC_RELEASE_CHECKLIST.md)
- [Release notes draft](docs/RELEASE_NOTES_v0.2.0-poc.md)

過去のdiagnostic procedureとcaptureはresearch-onlyです。production runtime moduleに
含まれず、通常利用にも必要ありません。

## コントリビューション

community memberはIssueを作成し、新しいgame versionをテストし、法的に安全な
hash/offset findingを共有し、GitHub forkを使い、Pull Requestを送ることができます。
新versionの報告には、次の情報を含めると役立ちます。

```text
game version / versionCode
Android or emulator environment
bootstrap result
60 FPS result
animation result
legally safe hashes or offset findings
relevant logs
regression description
```

APK、split APK、`libil2cpp.so`、`libunity.so`、`global-metadata.dat`、extracted
assetなど、その他のproprietary game fileをuploadしないでください。

## ライセンス

正式なライセンス本文は英語の[LICENSE](LICENSE)です。このrepositoryのcodeと
documentationはsource-available licenseで提供されます。study、個人利用および
non-commercial build、private modification、GitHub forkでのcollaboration、
upstream contributionを認めます。

一方、compiled moduleのredistribution、source packageのrehost、commercial use、
third-party game contentの配布を許可するものではありません。OSI-approved
open-source licenseであるとは表明しておらず、法的review済みという意味でも
ありません。利用前に英語のLICENSE本文を確認してください。

## 法的免責

これは非公式かつ独立したresearch projectです。Nintendo、The Pokémon Company、
Game Freak、Creatures、BlueStacks、その他のthird-party rights holderと提携せず、
承認も受けていません。Pokémon Champions、Pokémon、Unity、BlueStacks、および
関連する名称・contentは、それぞれの権利者に帰属します。

利用者は自分で用意した正規のgame installationを使用してください。このrepository
はgameまたはそのproprietary fileを配布しません。
