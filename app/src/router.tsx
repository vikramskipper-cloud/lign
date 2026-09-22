import { createBrowserRouter, Navigate, Outlet, useLocation } from 'react-router'
import { AuthGate } from '@/auth/AuthGate'
import { SignInScreen } from '@/auth/SignInScreen'
import { SignUpScreen } from '@/auth/SignUpScreen'
import { ResetPasswordScreen } from '@/auth/ResetPasswordScreen'
import { NoAccessScreen } from '@/auth/NoAccessScreen'
import { HomeScreen } from '@/features/home/HomeScreen'
import { WorkspacePeopleScreen } from '@/features/access/WorkspacePeopleScreen'
import { WorkspaceSettingsScreen } from '@/features/access/WorkspaceSettingsScreen'
import { ProjectPeopleScreen } from '@/features/access/ProjectPeopleScreen'
import { InviteClaimScreen } from '@/auth/InviteClaimScreen'
import { DeepLinkResolver } from '@/auth/DeepLinkResolver'
import { RootLayout } from '@/shell/RootLayout'
import { WorkspaceLayout } from '@/shell/WorkspaceLayout'
import { ProjectLayout } from '@/shell/ProjectLayout'
import { NotFound } from '@/shell/NotFound'
import { WorkspacePicker } from '@/routes/WorkspacePicker'
import {

} from '@/routes/stubs'
import {
  ProjectListScreen,
  ProjectListHandle,
} from '@/features/projects/ProjectListScreen'
import {
  ProjectOverviewScreen,
  ProjectOverviewHandle,
} from '@/features/projects/ProjectOverviewScreen'
import { DesignsScreen, DesignsHandle } from '@/features/designs/DesignsScreen'
import {
  DesignWorkspaceScreen,
  DesignWorkspaceHandle,
} from '@/features/design-workspace/DesignWorkspaceScreen'
import {
  WorkspaceReviewsScreen,
  WorkspaceReviewsHandle,
} from '@/features/reviews/WorkspaceReviewsScreen'
import {
  ProjectReviewsScreen,
  ProjectReviewsHandle,
} from '@/features/reviews/ProjectReviewsScreen'
import {
  ReviewDetailScreen,
  ReviewDetailHandle,
} from '@/features/reviews/ReviewDetailScreen'
import {
  WorkspaceApprovalsScreen,
  WorkspaceApprovalsHandle,
} from '@/features/approvals/WorkspaceApprovalsScreen'
import {
  ProjectApprovalsScreen,
  ProjectApprovalsHandle,
} from '@/features/approvals/ProjectApprovalsScreen'
import {
  ApprovalDetailScreen,
  ApprovalDetailHandle,
} from '@/features/approvals/ApprovalDetailScreen'
import {
  WorkspaceRequirementsScreen,
  WorkspaceRequirementsHandle,
} from '@/features/requirements/WorkspaceRequirementsScreen'
import {
  ProjectRequirementsScreen,
  ProjectRequirementsHandle,
} from '@/features/requirements/ProjectRequirementsScreen'
import {
  RequirementDetailScreen,
  RequirementDetailHandle,
} from '@/features/requirements/RequirementDetailScreen'
import {
  WorkspaceReleasesScreen,
  WorkspaceReleasesHandle,
} from '@/features/releases/WorkspaceReleasesScreen'
import { InboxScreen, InboxHandle } from '@/features/notifications/InboxScreen'
import {
  ProjectReleasesScreen,
  ProjectReleasesHandle,
} from '@/features/releases/ProjectReleasesScreen'
import {
  ReleaseDetailScreen,
  ReleaseDetailHandle,
} from '@/features/releases/ReleaseDetailScreen'

function ReviewDeepLink() {
  return <DeepLinkResolver kind="review" />
}
function ApprovalDeepLink() {
  return <DeepLinkResolver kind="approval" />
}
function ApproverDeepLink() {
  return <DeepLinkResolver kind="approver" />
}
function CommentDeepLink() {
  return <DeepLinkResolver kind="comment" />
}
function AnnotationDeepLink() {
  return <DeepLinkResolver kind="annotation" />
}
function ReviewerDeepLink() {
  return <DeepLinkResolver kind="reviewer" />
}
function RequirementDeepLink() {
  return <DeepLinkResolver kind="requirement" />
}
function ReleaseDeepLink() {
  return <DeepLinkResolver kind="release" />
}
function NotificationDeepLink() {
  return <DeepLinkResolver kind="notification" />
}

function Gated() {
  return (
    <AuthGate>
      <Outlet />
    </AuthGate>
  )
}

/**
 * Redirect that carries the query string and hash across.
 *
 * `<Navigate to="/x">` drops them, which here would silently discard the
 * ?returnTo= on the legacy /signin alias — turning a deep link into a landing
 * on the dashboard — and the ?ws= on /.
 */
function Alias({ to }: { to: string }) {
  const { search, hash } = useLocation()
  return <Navigate to={`${to}${search}${hash}`} replace />
}

export const router = createBrowserRouter([
  // Canonical auth paths are hyphenated. The unhyphenated spellings are kept
  // as redirects, not duplicates: password-reset emails already in inboxes
  // point at /signin, and one page served from two URLs is the thing this
  // rename is undoing.
  { path: '/sign-in', element: <SignInScreen /> },
  { path: '/signin', element: <Alias to="/sign-in" /> },
  { path: '/sign-up', element: <SignUpScreen /> },
  { path: '/signup', element: <Alias to="/sign-up" /> },
  { path: '/reset-password', element: <ResetPasswordScreen /> },
  { path: '/invite/:token', element: <InviteClaimScreen /> },
  // The account home lives at /dashboard and "/" is its front door. This sits
  // OUTSIDE Gated deliberately: a signed-out visit to "/" then bounces as
  // /sign-in?returnTo=/dashboard, so the post-login destination is the real
  // path rather than another redirect hop.
  { path: '/', element: <Alias to="/dashboard" /> },
  {
    element: <Gated />,
    children: [
      // Signed in, but nothing to open. Deliberately OUTSIDE RootLayout: the
      // nav rail and workspace switcher would have nothing to show.
      { path: '/no-access', element: <NoAccessScreen /> },
      {
        element: <RootLayout />,
        children: [
          { path: '/dashboard', element: <HomeScreen /> },
          { path: '/workspace-picker', element: <WorkspacePicker /> },
          { path: '/deep/review/:id', element: <ReviewDeepLink /> },
          { path: '/deep/reviewer/:id', element: <ReviewerDeepLink /> },
          { path: '/deep/approval/:id', element: <ApprovalDeepLink /> },
          { path: '/deep/approver/:id', element: <ApproverDeepLink /> },
          { path: '/deep/comment/:id', element: <CommentDeepLink /> },
          { path: '/deep/annotation/:id', element: <AnnotationDeepLink /> },
          { path: '/deep/requirement/:id', element: <RequirementDeepLink /> },
          { path: '/deep/release/:id', element: <ReleaseDeepLink /> },
          { path: '/deep/notification/:id', element: <NotificationDeepLink /> },
          {
            path: '/workspace/:ws_id',
            element: <WorkspaceLayout />,
            handle: WorkspaceLayout.handle,
            children: [
              { index: true, element: <Navigate to="projects" replace /> },
              { path: 'projects', element: <ProjectListScreen />, handle: ProjectListHandle },
              { path: 'reviews', element: <WorkspaceReviewsScreen />, handle: WorkspaceReviewsHandle },
              { path: 'approvals', element: <WorkspaceApprovalsScreen />, handle: WorkspaceApprovalsHandle },
              { path: 'requirements', element: <WorkspaceRequirementsScreen />, handle: WorkspaceRequirementsHandle },
              { path: 'releases', element: <WorkspaceReleasesScreen />, handle: WorkspaceReleasesHandle },
              { path: 'inbox', element: <InboxScreen />, handle: InboxHandle },
              { path: 'people', element: <WorkspacePeopleScreen />, handle: WorkspacePeopleScreen.handle },
              { path: 'settings', element: <WorkspaceSettingsScreen />, handle: WorkspaceSettingsScreen.handle },
              {
                path: 'project/:proj_id',
                element: <ProjectLayout />,
                handle: ProjectLayout.handle,
                children: [
                  { index: true, element: <Navigate to="overview" replace /> },
                  { path: 'overview', element: <ProjectOverviewScreen />, handle: ProjectOverviewHandle },
                  { path: 'designs', element: <DesignsScreen />, handle: DesignsHandle },
                  { path: 'reviews', element: <ProjectReviewsScreen />, handle: ProjectReviewsHandle },
                  { path: 'review/:review_id', element: <ReviewDetailScreen />, handle: ReviewDetailHandle },
                  { path: 'review/:review_id/round/:round_number', element: <ReviewDetailScreen />, handle: ReviewDetailHandle },
                  { path: 'approvals', element: <ProjectApprovalsScreen />, handle: ProjectApprovalsHandle },
                  { path: 'approval/:approval_id', element: <ApprovalDetailScreen />, handle: ApprovalDetailHandle },
                  { path: 'requirements', element: <ProjectRequirementsScreen />, handle: ProjectRequirementsHandle },
                  { path: 'requirement/:requirement_id', element: <RequirementDetailScreen />, handle: RequirementDetailHandle },
                  { path: 'asset/:asset_id', element: <DesignWorkspaceScreen />, handle: DesignWorkspaceHandle },
                  { path: 'asset/:asset_id/v/:v_id', element: <DesignWorkspaceScreen />, handle: DesignWorkspaceHandle },
                  { path: 'asset/:asset_id/v/:v_id/file/:file_id', element: <DesignWorkspaceScreen />, handle: DesignWorkspaceHandle },
                  { path: 'releases', element: <ProjectReleasesScreen />, handle: ProjectReleasesHandle },
                  { path: 'release/:release_id', element: <ReleaseDetailScreen />, handle: ReleaseDetailHandle },
                  { path: 'people', element: <ProjectPeopleScreen />, handle: ProjectPeopleScreen.handle },
                ],
              },
            ],
          },
          { path: '*', element: <NotFound /> },
        ],
      },
    ],
  },
])
