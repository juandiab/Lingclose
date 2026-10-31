extension MedicalReportDocument {
    /// La tabla opcional o de glucosa con ese `id` (el del flujo), si el documento la trae.
    func table(id: String) -> MedicalTable? {
        [agpTable, slots, weekly, meals, nights, exercise, bodySummary, bodyByDay, notes]
            .compactMap { $0 }
            .first { $0.id == id }
    }
}
