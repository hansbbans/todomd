import SwiftUI

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer

    let path: String

    @State private var editState: TaskEditState?
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if editState != nil {
                Form {
                    Section("Title") {
                        TextField("Title", text: binding(\.title))
                        TextField("Description", text: binding(\.subtitle))
                    }

                    Section("Status") {
                        Picker("Status", selection: binding(\.status)) {
                            ForEach(TaskStatus.allCases, id: \.self) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }

                        Toggle("Flagged", isOn: binding(\.flagged))

                        Picker("Priority", selection: binding(\.priority)) {
                            ForEach(TaskPriority.allCases, id: \.self) { priority in
                                Text(priority.rawValue).tag(priority)
                            }
                        }
                    }

                    Section("Dates") {
                        Toggle("Due", isOn: binding(\.hasDue))
                        if binding(\.hasDue).wrappedValue {
                            DatePicker("Due date", selection: binding(\.dueDate), displayedComponents: .date)
                        }

                        Toggle("Defer", isOn: binding(\.hasDefer))
                        if binding(\.hasDefer).wrappedValue {
                            DatePicker("Defer until", selection: binding(\.deferDate), displayedComponents: .date)
                        }

                        Toggle("Scheduled", isOn: binding(\.hasScheduled))
                        if binding(\.hasScheduled).wrappedValue {
                            DatePicker("Scheduled date", selection: binding(\.scheduledDate), displayedComponents: .date)
                        }
                    }

                    Section("Planning") {
                        Toggle("Estimated minutes", isOn: binding(\.hasEstimatedMinutes))
                        if binding(\.hasEstimatedMinutes).wrappedValue {
                            Stepper(value: binding(\.estimatedMinutes), in: 1...720, step: 5) {
                                Text("\(binding(\.estimatedMinutes).wrappedValue) minutes")
                            }
                        }

                        TextField("Area", text: binding(\.area))
                        TextField("Project", text: binding(\.project))
                        TextField("Tags (comma separated)", text: binding(\.tagsText))
                        TextField("Recurrence RRULE", text: binding(\.recurrence))
                            .textInputAutocapitalization(.never)
                    }

                    Section("Notes") {
                        TextEditor(text: binding(\.body))
                            .frame(minHeight: 180)
                            .font(.body.monospaced())
                    }

                    Section("Metadata") {
                        LabeledContent("Source", value: binding(\.source).wrappedValue)
                        LabeledContent("Created", value: DateCoding.encode(binding(\.createdAt).wrappedValue))
                        if let modified = binding(\.modifiedAt).wrappedValue {
                            LabeledContent("Modified", value: DateCoding.encode(modified))
                        }
                        if let completed = binding(\.completedAt).wrappedValue {
                            LabeledContent("Completed", value: DateCoding.encode(completed))
                        }
                    }

                    Section {
                        Button("Save") {
                            save()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Delete Task", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            } else {
                ContentUnavailableView("Task Unavailable", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editState = container.makeEditState(path: path)
        }
        .alert(
            "Delete Task",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("Delete", role: .destructive) {
                    if container.deleteTask(path: path) {
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("This permanently deletes the task file.")
            }
        )
        .alert(
            "Save Failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            actions: { Button("OK", role: .cancel) { errorMessage = nil } },
            message: { Text(errorMessage ?? "") }
        )
    }

    private func save() {
        guard let editState else { return }
        let didSave = container.updateTask(path: path, editState: editState)
        if didSave {
            self.editState = container.makeEditState(path: path)
        } else {
            errorMessage = "Could not save this task. Please check required fields and try again."
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TaskEditState, T>) -> Binding<T> {
        Binding(
            get: {
                guard let editState else {
                    fatalError("TaskEditState missing")
                }
                return editState[keyPath: keyPath]
            },
            set: { newValue in
                guard var editState else { return }
                editState[keyPath: keyPath] = newValue
                self.editState = editState
            }
        )
    }
}
