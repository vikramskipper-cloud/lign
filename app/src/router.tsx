import { createBrowserRouter, Navigate, Outlet } from 'react-router'
import { AuthGate } from '@/auth/AuthGate'
import { SignInScreen } from '@/auth/SignInScreen'
import { InviteClaimScreen } from '@/auth/InviteClaimScreen'
import { DeepLinkResolver } from '@/auth/DeepLinkResolver'
import { RootLayout } from '@/shell/RootLayout'
import { WorkspaceLayout } from '@/shell/WorkspaceLayout'
import { ProjectLayout } from '@/shell/ProjectLayout'
import { NotFound } from '@/shell/NotFound'
import { RootRedirect } from '@/routes/RootRedirect'
import { WorkspacePicker } from '@/routes/WorkspacePicker'
import {
  ProjectPeopleStub,
  WorkspacePeopleStub,
  WorkspaceSettingsStub,
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

export const router = createBrowserRouter([
  { path: '/signin', element: <SignInScreen /> },
  { path: '/invite/:token', element: <InviteClaimScreen /> },
  {
    element: <Gated />,
    children: [
      {
        element: <RootLayout />,
        children: [
          { path: '/', element: <RootRedirect /> },
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
              { path: 'people', element: <WorkspacePeopleStub />, handle: WorkspacePeopleStub.handle },
              { path: 'settings', element: <WorkspaceSettingsStub />, handle: WorkspaceSettingsStub.handle },
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
                  { path: 'people', element: <ProjectPeopleStub />, handle: ProjectPeopleStub.handle },
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
