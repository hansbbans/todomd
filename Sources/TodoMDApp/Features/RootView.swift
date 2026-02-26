import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var quickEntryTitle = ""
    @State private var quickEntryDateText = ""
    @State private var showingQuickEntry = false
    @State private var navigationPath = NavigationPath()
    @State private var pathsCompleting: Set<String> = []
    @State private var pendingDeletePath: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    Picker("View", selection: $container.selectedView) {
                        Text("Inbox").tag(ViewIdentifier.builtIn(.inbox))
                        Text("Today").tag(ViewIdentifier.builtIn(.today))
                        Text("Upcoming").tag(ViewIdentifier.builtIn(.upcoming))
                        Text("Anytime").tag(ViewIdentifier.builtIn(.anytime))
                        Text("Someday").tag(ViewIdentifier.builtIn(.someday))
                        Text("Flagged").tag(ViewIdentifier.builtIn(.flagged))
                    }
                    .pickerStyle(.segmented)
                }

                if !container.conflicts.isEmpty {
                    Section {
                        NavigationLink {
                            ConflictResolutionView()
                        } label: {
                            Label("Resolve \(container.conflicts.count) conflict(s)", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if !container.diagnostics.isEmpty {
                    Section {
                        NavigationLink {
                            UnparseableFilesView()
                        } label: {
                            Label("Review \(container.diagnostics.count) unparseable file(s)", systemImage: "doc.badge.gearshape")
                                .foregroundStyle(.yellow)
                        }
                    }
                }

                if container.selectedView == .builtIn(.today) {
                    ForEach(container.todaySections()) { section in
                        Section(section.group.rawValue) {
                            ForEach(section.records) { record in
                                taskRowItem(record)
                            }
                        }
                    }
                } else {
                    Section("Tasks") {
                        ForEach(container.filteredRecords()) { record in
                            taskRowItem(record)
                        }
                        .onMove { source, destination in
                            var reordered = container.filteredRecords()
                            reordered.move(fromOffsets: source, toOffset: destination)
                            container.saveManualOrder(filenames: reordered.map { $0.identity.filename })
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { path in
                TaskDetailView(path: path)
            }
            .navigationTitle("todo.md")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }

                        Button {
                            showingQuickEntry = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        EditButton()
                        NavigationLink {
                            DebugView()
                        } label: {
                            Image(systemName: "ladybug")
                        }
                    }
                }
            }
            .refreshable {
                container.refresh()
            }
            .sheet(isPresented: $showingQuickEntry) {
                NavigationStack {
                    Form {
                        TextField("Title", text: $quickEntryTitle)
                        TextField("Date phrase (optional)", text: $quickEntryDateText)
                    }
                    .navigationTitle("Quick Entry")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingQuickEntry = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                container.createTask(
                                    title: quickEntryTitle,
                                    naturalDate: quickEntryDateText.isEmpty ? nil : quickEntryDateText
                                )
                                quickEntryTitle = ""
                                quickEntryDateText = ""
                                showingQuickEntry = false
                            }
                            .disabled(quickEntryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .alert(
                "High Ingestion Volume",
                isPresented: Binding(
                    get: { container.rateLimitAlertMessage != nil },
                    set: { isPresented in
                        if !isPresented { container.rateLimitAlertMessage = nil }
                    }
                ),
                actions: {
                    Button("OK", role: .cancel) { container.rateLimitAlertMessage = nil }
                },
                message: {
                    Text(container.rateLimitAlertMessage ?? "")
                }
            )
            .alert(
                "Delete Task",
                isPresented: Binding(
                    get: { pendingDeletePath != nil },
                    set: { isPresented in
                        if !isPresented { pendingDeletePath = nil }
                    }
                ),
                actions: {
                    Button("Delete", role: .destructive) {
                        if let pendingDeletePath {
                            _ = container.deleteTask(path: pendingDeletePath)
                            self.pendingDeletePath = nil
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        pendingDeletePath = nil
                    }
                },
                message: {
                    Text("This removes the task markdown file.")
                }
            )
            .alert(
                "Link Error",
                isPresented: Binding(
                    get: { container.urlRoutingErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented { container.urlRoutingErrorMessage = nil }
                    }
                ),
                actions: {
                    Button("OK", role: .cancel) {
                        container.urlRoutingErrorMessage = nil
                    }
                },
                message: {
                    Text(container.urlRoutingErrorMessage ?? "")
                }
            )
            .onChange(of: container.navigationTaskPath) { _, newPath in
                guard let newPath else { return }
                navigationPath.append(newPath)
                container.clearPendingNavigationPath()
            }
            .onAppear {
                if let pending = container.navigationTaskPath {
                    navigationPath.append(pending)
                    container.clearPendingNavigationPath()
                }
            }
        }
    }

    private func completeWithAnimation(path: String) {
        guard !pathsCompleting.contains(path) else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            _ = pathsCompleting.insert(path)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            container.complete(path: path)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                _ = pathsCompleting.remove(path)
            }
        }
    }

    private func taskRowItem(_ record: TaskRecord) -> some View {
        NavigationLink(value: record.identity.path) {
            TaskRow(record: record)
        }
        .contextMenu {
            Button("Complete") {
                completeWithAnimation(path: record.identity.path)
            }

            Button("Defer to Tomorrow") {
                _ = container.deferToTomorrow(path: record.identity.path)
            }

            Button(record.document.frontmatter.flagged ? "Remove Flag" : "Flag") {
                _ = container.toggleFlag(path: record.identity.path)
            }

            Button("Delete", role: .destructive) {
                pendingDeletePath = record.identity.path
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                completeWithAnimation(path: record.identity.path)
            } label: {
                Label("Complete", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                _ = container.deferToTomorrow(path: record.identity.path)
            } label: {
                Label("Tomorrow", systemImage: "arrow.turn.down.right")
            }
            .tint(.blue)
        }
        .opacity(pathsCompleting.contains(record.identity.path) ? 0.4 : 1.0)
        .scaleEffect(pathsCompleting.contains(record.identity.path) ? 0.96 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: pathsCompleting)
    }
}

private struct TaskRow: View {
    let record: TaskRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: record.document.frontmatter.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(record.document.frontmatter.status == .done ? .green : .secondary)
                Text(record.document.frontmatter.title)
                    .font(.body)
                    .lineLimit(1)
                if record.document.frontmatter.flagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                }
            }

            if let description = record.document.frontmatter.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let due = record.document.frontmatter.due {
                    Text("Due \(due.isoString)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if record.document.frontmatter.source != "user" {
                    Label(record.document.frontmatter.source, systemImage: "tray.and.arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let estimate = record.document.frontmatter.estimatedMinutes {
                    Text("\(estimate)m")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
