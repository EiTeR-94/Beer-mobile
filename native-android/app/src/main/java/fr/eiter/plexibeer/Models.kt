package fr.eiter.plexibeer

data class MeResponse(
    val user: String?,
    val auth: Boolean,
    val isAdmin: Boolean = false,
    val isInvite: Boolean = false
)

data class CheckinItem(
    val id: Int,
    val beerName: String,
    val brewery: String,
    val style: String,
    val rating: Double?,
    val comment: String?,
    // add more fields as in iOS Models
)

data class LoginResponse(
    val ok: Boolean,
    val user: String?,
    val isAdmin: Boolean = false,
    val error: String? = null
)