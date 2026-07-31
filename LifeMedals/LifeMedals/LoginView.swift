import SwiftUI

/// v1 keeps this as a visual entry point only; no credentials or permissions are created.
struct LoginView: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            GlassBackground()

            GlassEffectContainer(spacing: 18) {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "medal.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 72, height: 72)
                            .glassEffect(.regular.tint(.orange.opacity(0.12)), in: Circle())

                        VStack(spacing: 7) {
                            Text("人生勋章")
                                .font(.largeTitle.bold())
                            Text("把想做的事，变成一份值得完成的契约。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 12) {
                        Button(action: onContinue) {
                            HStack(spacing: 9) {
                                Image(systemName: "applelogo")
                                Text("使用 Apple 登录")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .glassEffect(
                            .regular.tint(Color.accentColor.opacity(0.13)).interactive(),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )

                        Button("暂时跳过", action: onContinue)
                            .buttonStyle(.plain)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }

                    Text("当前版本仅保存在本机，不会创建账户。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(34)
                .frame(width: 390)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .preferredColorScheme(.light)
    }
}

#Preview {
    LoginView(onContinue: {})
}
