# Security Policy

## 基本方針

MeetingFlow AIは会議という機密性の高いデータを扱うため、MVPでは攻撃面を小さくするLocal-first構成を採用します。外部AI APIや独自バックエンドは使用しません。オンライン字幕のみiOS標準のApple Speechを利用し、オフライン対応端末では端末内認識へ切り替えます。

## 実装済み対策

- App Sandbox内のDocuments/Recordingsへm4a音声を保存
- `FileProtectionType.complete` によるロック中の音声保護
- 外部入力のファイル名を `lastPathComponent` と照合し、ディレクトリ遡 traversalを拒否
- ATSで任意の非TLS通信を不許可
- NWPathMonitorで接続状態を監視し、オフライン時だけSpeech認識を `requiresOnDeviceRecognition = true` に固定
- SwiftDataのcascade削除と音声ファイル削除を同じユーザー操作から実行
- APIキー候補、署名鍵、Provisioning ProfileをGit対象外に設定
- メール自動送信を行わず、共有前にユーザー確認を要求
- Privacy Manifestでトラッキング・データ収集なしを宣言

## クラウドAI追加時の必須条件

1. ベンダーAPIキーをiOSアプリ、plist、xcconfig、Git履歴へ含めない。
2. 認証済みの自社バックエンドから短期アクセストークンを発行する。
3. TLS 1.2以上、入力サイズ制限、レート制限、タイムアウト、再試行上限を設定する。
4. 会議ごとの送信同意、送信範囲、保存期間、削除方法をUIで明示する。
5. ログへ音声、逐字稿、メールアドレス、認証情報を記録しない。
6. 依存関係の脆弱性監視、鍵のローテーション、インシデント対応手順を用意する。
7. App Privacy回答とプライバシーポリシーを実態に合わせて更新する。

## 将来の改善

現在のMVPにはApp Lockを実装していません。今後、利用場面と脅威モデルを確認した上で、以下を検討します。

- LocalAuthenticationを利用したFace ID / Touch ID対応のApp Lock
- 機密性の高い端末内データに対する追加暗号化
- Keychainを利用した暗号鍵管理

## 報告

公開前のポートフォリオ段階では、Issueに会議データや秘密情報を添付しないでください。実運用する場合は公開Issueと分離した脆弱性報告窓口を設定してください。
