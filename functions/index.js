const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
admin.initializeApp();

exports.notifyGroupMembers = onDocumentCreated(
    "groups/{groupId}/messages/{messageId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data();
      const groupId = event.params.groupId;
      const senderId = msg.senderId || "";
      const senderName = msg.senderName || "Member";
      const text = (msg.text || "").trim();
      if (!text) return;

      const db = admin.firestore();
      const groupDoc = await db.collection("groups").doc(groupId).get();
      if (!groupDoc.exists) return;

      const groupData = groupDoc.data();
      const groupName = groupData.name || "Shared Expense";
      const members = groupData.members || [];

      const recipientIds = members.filter((uid) => uid !== senderId);
      if (recipientIds.length === 0) return;

      const userDocs = await Promise.all(
          recipientIds.map((uid) => db.collection("users").doc(uid).get()),
      );

      const tokens = userDocs
          .map((doc) => (doc.exists ? doc.data().fcmToken : null))
          .filter((token) => typeof token === "string" && token.length > 0);

      if (tokens.length === 0) return;

      const isExpense =
        text.startsWith("💵") || text.includes("added shared expense:");

      const channelId = isExpense ?
        "group_expenses_channel" :
        "group_messages_channel";

      await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: isExpense ? `New Group Expense • ${groupName}` : groupName,
          body: isExpense ? text : `${senderName}: ${text}`,
        },
        android: {
          priority: "high",
          notification: {
            channelId,
            sound: "default",
          },
        },
        data: {
          groupId,
        },
      });
    },
);