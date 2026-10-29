import SwiftUI

struct ShareTripView: View {
    @State private var viewModel: ShareTripViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ShareTripViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                        .foregroundStyle(.white)
                        .frame(width: 90, height: 90)
                        .background(Theme.accentGradient, in: Circle())
                        .accessibilityHidden(true)
                    VStack(spacing: 6) {
                        Text("Plan \(viewModel.trip?.name ?? "this trip") together").font(.title3.bold())
                        Text("Friends who join see the plan, packing list and expenses, and their changes appear on your phone too. Journal memories stay private.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    switch viewModel.state {
                    case .creating:
                        ProgressView("Making a code…").padding(.vertical, 30)
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("Couldn't make a code", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Try Again") { Task { await viewModel.createInvite() } }
                        }
                    case .ready:
                        codeCard
                    }

                    if !viewModel.joinedMembers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("On RoamPulse")
                            ForEach(viewModel.joinedMembers) { member in
                                HStack(spacing: 12) {
                                    AvatarView(member: member, size: 36)
                                    Text(member.isMe ? "\(member.name) (you)" : member.name)
                                    Spacer()
                                    Image(systemName: "checkmark.icloud").foregroundStyle(.green)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .card()
                    }
                }
                .padding(20)
            }
            .background(Theme.card)
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await viewModel.createInvite() }
        }
        .presentationDragIndicator(.visible)
    }

    private var codeCard: some View {
        VStack(spacing: 14) {
            Text("Invite code").font(.subheadline).foregroundStyle(.secondary)
            Text(viewModel.formattedCode)
                .scaledFont(size: 40, weight: .bold, design: .monospaced)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)
                .accessibilityLabel("Invite code \(viewModel.formattedCode.map { String($0) }.joined(separator: " "))")
            Text(viewModel.expiryText).font(.footnote).foregroundStyle(.secondary)
            ShareLink(item: viewModel.shareMessage) {
                Label("Send Code", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())
            .sensoryFeedback(.success, trigger: viewModel.formattedCode)
        }
        .card(padding: 20)
    }
}

struct JoinTripView: View {
    @State private var viewModel: JoinTripViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFocused: Bool

    init(viewModel: JoinTripViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch viewModel.step {
                    case .enterCode:
                        enterCode
                    case .chooseMember(let invite):
                        chooseMember(invite)
                    case .joined(let tripName):
                        joined(tripName)
                    }

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(20)
                .motionAnimation(.snappy, value: viewModel.step)
            }
            .background(Theme.card)
            .navigationTitle("Join a Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.step == .enterCode ? "Cancel" : "Close") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var enterCode: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Enter the code a friend sent you to see their trip here and share its plan and expenses.")
                .foregroundStyle(.secondary)
            FormField(label: "Invite code") {
                TextField("K7QM-2XHA", text: $viewModel.code)
                    .font(.title2.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($codeFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await viewModel.findTrip() } }
            }
            Button {
                Task { await viewModel.findTrip() }
            } label: {
                if viewModel.isWorking { ProgressView().tint(.white) } else { Text("Find Trip") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.code.isEmpty || viewModel.isWorking)
        }
        .onAppear { codeFocused = true }
    }

    private func chooseMember(_ invite: TripInvite) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invite.tripName).font(.title2.bold())
                Text("\(invite.destination) • \(invite.startDate.text("d MMM"))–\(invite.endDate.text("d MMM yyyy"))")
                    .foregroundStyle(.secondary)
                Text("Shared by \(invite.ownerName)").font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            SectionLabel("Which one are you?")
            VStack(spacing: 0) {
                ForEach(invite.availableMembers) { member in
                    memberRow(title: member.name, isSelected: viewModel.selectedMemberID == member.id) {
                        Text(member.initials)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color(hex: UInt32(member.colorHex)), in: Circle())
                    } select: {
                        viewModel.selectedMemberID = member.id
                    }
                    Divider().padding(.leading, 60)
                }
                memberRow(title: "I'm not on the list", isSelected: viewModel.selectedMemberID == nil) {
                    Image(systemName: "person.badge.plus")
                        .frame(width: 36, height: 36)
                        .background(Theme.raised, in: Circle())
                } select: {
                    viewModel.selectedMemberID = nil
                }
            }
            .card(padding: 0)
            Text("Expenses already split with that person become yours.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.join() }
            } label: {
                if viewModel.isWorking { ProgressView().tint(.white) } else { Text("Join Trip") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isWorking)

            Button("Use a different code") { viewModel.startOver() }
                .frame(maxWidth: .infinity)
        }
    }

    private func memberRow<Icon: View>(title: String, isSelected: Bool, @ViewBuilder icon: () -> Icon,
                                       select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 12) {
                icon()
                Text(title)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                    .font(.title3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func joined(_ tripName: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .accessibilityHidden(true)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: tripName)
            Text("You've joined \(tripName)").font(.title2.bold())
            Text("It will appear in Trips in a moment. Changes you make are shared with the group.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .sensoryFeedback(.success, trigger: tripName)
    }
}
